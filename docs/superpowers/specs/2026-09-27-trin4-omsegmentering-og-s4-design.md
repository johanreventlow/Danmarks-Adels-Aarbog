# Trin 4 · omsegmentering af en posts klausuler + S4 — design

**Status:** revision 3 (2026-09-27) efter plan-review runde 1 (NO-GO: 1 BLOCKER, 5 MAJOR, 6 MINOR) og runde 2 (GO med rettelser: 1 MAJOR, 7 MINOR). Alle fund efterprøvet i koden og indarbejdet, se §6. Planbudgettet (2) er brugt.
**GO:** projektejeren 2026-09-27, med anbefalingerne i §5.1-5.3 (sæt-nummer på rækken; udgaveneutral, ingen 1939-kode; smal tilladelsesliste for læser-vagten). **Beslutning:** `decisions.md` 2026-09-27
(omsegmentering før 4.4, skridt 3-4). **Review-budget:** DDL ⇒ 2 + 2 (decisions 2026-09-23).
**Afløser:** intet; supplerer trin 4-spec'en §4.1 (klausullaget) og §7 (proposed-ingest).

## 1. Kobling (roadmappens seks adgangskrav)

| | |
| --- | --- |
| Roadmapmål | Trin 4 (#147/#148): fortolkningskæden og klausulgranularitet |
| Værdikædeled | Klausullaget (evidens) → proposed-ingest |
| Leverancetype | Generel writer-operation (udgaveneutral) + rettelse af den generelle forslagswriter |
| Redaktionel værdi | 42 af 2018-20's 101 flerklausul-poster får hele sætninger i stedet for stumper, og 9 poster får rettede flag (6 af dem en anden startdisposition); modellen og redaktøren læser meningsbærende klausuler (pilotens to kendte fejl ligger i dem) |
| Færdigbevis | Rehearsal mod et frisk prod-dump: 51 poster revideret (42 spans + 9 kun flag), projektionen afstemt, 0 kanonisk delta, `anon` uændret; derefter prod-kørsel efter GO |
| Erstatter | Restore som eneste vej til at rette klausuler (beslutning 2026-09-17) |

## 2. Udgangspunkt (målt i koden)

- Klausuler er `private.source_observation`-rækker (`observation_kind='clause'`) under én
  helpost (`parent_observation_id`), med `UNIQUE(parent_observation_id, clause_ordinal)`
  (`ux_source_observation_clause_ordinal`) og append-only-trigger. De kan hverken slettes,
  ændres eller få en ny række med samme ordinal.
- `private.write_clause_evidence` afviser en post, der har klausuler
  (`REIMPORT_WRITER_CLAUSE_EVIDENCE_EXISTS`, `schema.sql:3392`).
- Hver klausul har en append-only dispositionsledger (`private.clause_disposition`,
  versioneret); maskinelle koder: `afventer_fortolkning`, `fortolkning_foreslaaet`,
  `afventer_identitet`, `maskinelt_flagget`, `strukturel`.
- **S4:** `private.write_interpretation_proposal` afviser kun en dublet i *samme* batch
  (`schema.sql:3649-3653`). Et nyt batch for samme post lægger nye `proposed` ved siden af de
  gamle. Trin 4-spec'en §7 kræver noget andet: »Genudtræk af en allerede ingestet record kræver
  en menneskelig `superseded`-beslutning og er trin 6.«
- Prod pr. 2026-09-27: 591 poster, 868 klausuler, **0 fortolkninger** (4.4 er parkeret). Ingen
  flade skriver menneskelige klausuldispositioner (hverken web, mobil eller en `red_*`-RPC); det
  efterprøves i rehearsalens dump.

## 3. Design

### 3.1 Klausulsæt som generation på rækken

Én ny nullable kolonne på `private.source_observation`: `clause_set_seq integer CHECK (clause_set_seq >= 1)`,
**uden default**. En default ville blive skrevet i alle eksisterende rækker — også de 591
helposter og 1939's observationer — og kan ikke rettes bagefter, fordi tabellen er append-only
(review B1).

- **`NULL` på en klausul betyder sæt 1** (4.1c's 868 rækker står urørte). `validate_clause_observation`
  kræver `clause_set_seq IS NULL` på andre kinds og `IS NOT NULL` på *nye* klausulrækker;
  `write_clause_evidence` skriver fremover `1` eksplicit.
- **Unikhed:** indekset beholder navnet `ux_source_observation_clause_ordinal` og defineres om til
  `(parent_observation_id, coalesce(clause_set_seq,1), clause_ordinal)`. Samme navn er afgørende:
  den historiske blok i `db-migrations.sql` (`CREATE UNIQUE INDEX IF NOT EXISTS …`, ca. linje
  17511) bliver så en no-op ved genkørsel i stedet for at genskabe den gamle unikhed (review M1).
  Migrationen bygger det nye indeks under et midlertidigt navn, dropper det gamle og omdøber i
  én `DO`-blok, og kun når definitionen mangler `clause_set_seq`. Blokken står efter den
  historiske. `db-migrations.sql` kan ikke køre med `--single-transaction`, så uden én blok
  ville der være et vindue uden unikhedsindeks (review R2).
- **Sættenes form håndhæves i to lag** (review M2). Rækketriggeren tillader
  `seq = coalesce(max,0)+1`, hvor `max` tages over `coalesce(clause_set_seq,1)`, eller `seq = max`,
  når sættets eksisterende rækker har samme `extraction_run_id` som den nye (ét sæt = én kørsel).
  En ny post får derfor sæt 1. En udskudt constraint-trigger kræver tætte ordinaler `1..n` pr. sæt.
  Writerne kalder `SET CONSTRAINTS … IMMEDIATE` til sidst, så tjekket også kører i dry-run, der
  ruller tilbage. At et afsluttet sæt ikke kan få flere rækker, sikres af run-id-reglen, fordi en
  anden batch med samme manifest stopper på `CLAUSE_EVIDENCE_EXTRACTION_RUN_DRIFT`.
- **Aktuelt sæt** = højeste `coalesce(clause_set_seq,1)` pr. forælder. Ét view,
  `private.clause_observation_current` (`security_invoker`), er den eneste læsevej for »postens
  klausuler«.
- **Sættets identitet:** `private.clause_set_sha256(parent, seq)` er sha256 over den kanoniske JSON
  af en liste sorteret efter ordinal med `{ordinal, post_char_from, post_char_to, char_from,
  char_to, classification, flags, verbatim_sha256}` (review M3). Payloadens `char_from/char_to` er
  `post_char_*`, og `rendition_char_*` er `char_*`. Flag sorteres og dubletter fjernes i den
  kanoniske form. SQL-siden bruger `private.interpretation_proposal_canonical_json_text` (nøgler
  `COLLATE "C"`, ingen mellemrum), ikke `jsonb::text`. Python-siden bruger
  `json.dumps(sort_keys=True, separators=(",",":"), ensure_ascii=False)`. En test låser, at de to
  giver samme hash. Ledger-hashen fra `clause_segment.py` bruges *ikke*
  til dette: den dækker hverken flag eller tekst, og databasen kan ikke genskabe dens layout-stykker.
  Målt: 9 poster ændrer kun flag, og for 6 af dem giver det en anden startdisposition.

Valgt frem for alternativerne:

| Alternativ | Hvorfor ikke |
| --- | --- |
| Slette/ændre de gamle klausuler | Bryder invariant 1 (append-only) og proveniensen for 4.1c's batch |
| Markere de gamle som afløst på rækken | Kræver UPDATE af append-only rækker |
| Separat `clause_set`-tabel | Unikhedsindekset kan ikke se en anden tabel; rækken skal alligevel bære sæt-id'et. En tabel kan tilføjes senere, hvis sæt får egne metadata |
| Ny helpost | Writerne kræver præcis én helpost pr. forekomst (`CLAUSE_EVIDENCE_PARENT_AMBIGUOUS`) |
| Default `1` + engangs-backfill med triggeren slået fra | Kræver at slå append-only-værnet fra i prod; `NULL = 1` giver samme betydning uden det |

### 3.2 Ny writer-operation `clause_revision`

`private.write_clause_revision(batch, element, payload)` + `public.red_apply_reimport_clause_revision`,
element-id `clause-revision:<record_key>`. Payload = `clause_evidence`'s lukkede nøglesæt plus
`replaces_clause_set_seq` og `replaces_clause_set_sha256`.

Writeren:
1. Samme autorisation, lås, kontrakt- og anker-/rendition-/forælderkontroller som
   `write_clause_evidence` (fælles hjælpefunktion frem for kopi — to definitioner af samme
   kontrol glider fra hinanden). **Låserækkefølge** som `write_interpretation_proposal`:
   `source_record` FOR UPDATE, derefter helposten FOR UPDATE (review m6); `lock_reimport_writer`
   er pr. profil og serialiserer ikke på tværs af profiler.
2. Låser det aktuelle sæts klausulrækker med `FOR UPDATE`. Det er samme række, som
   dispositionstriggeren låser, så en samtidig disposition ikke kan nå ind under kontrollerne
   (review R2). **Afviser derefter fail-closed**, hvis
   - det aktuelle sæt ikke er `replaces_clause_set_seq`, eller `clause_set_sha256` (beregnet af
     rækkerne, ikke aflæst af eventen) ikke er `replaces_clause_set_sha256`
     (`CLAUSE_REVISION_BASE_DRIFT`);
   - en klausul i det aktuelle sæt citeres af en `interpretation_observation`
     (`CLAUSE_REVISION_HAS_INTERPRETATIONS`);
   - en klausul i det aktuelle sæt har en menneskelig disposition
     (`CLAUSE_REVISION_HAS_HUMAN_DISPOSITION`);
   - det nye sæts `clause_set_sha256` er lig det aktuelles (`CLAUSE_REVISION_NOOP`) — en uændret
     post hører ikke i manifestet. En ren flag-ændring er *ikke* en no-op.
3. Skriver det nye sæt (`clause_set_seq = gammelt+1`) med samme klausulvalidering og samme
   startdispositioner som `clause_evidence`.
4. Skriver pr. gammel klausul en maskinel disposition `erstattet` (ny kode i
   `clause_disposition_machine`) med batch- og manifestreference, så dispositionskøen ikke viser
   dem. Reglen er præcis (review m4 og R2): `erstattet` må kun skrives på en klausul *uden for*
   det aktuelle sæt og kun én gang. Alle andre dispositioner må kun skrives *inden for* det
   aktuelle sæt, og intet må komme efter `erstattet`.
5. `reimport_event` med `operation='clause_revision'`, `before` = gammelt sæts ledger-hash og
   antal, `after` = nyt.

Afgrænsningen i punkt 2 er bevidst: en omsegmentering af en post med forslag eller menneskelige
afgørelser er trin 6 (»superseded«-beslutningen). Operationen dækker præcis det, beslutningen
2026-09-27 kræver: prod før 4.4, hvor intet afhænger af klausulerne.

**Fortrydelse:** en ny `clause_revision` tilbage til den gamle profils segmentering (sæt 3 = sæt
1's spans). Det er append-only symmetrisk og kræver ingen restore — men kun, indtil 4.4 har
skrevet forslag, der citerer sæt 2 (så afviser `CLAUSE_REVISION_HAS_INTERPRETATIONS`), og det
kræver en revisionsprofil med de gamle regler og dermed et nyt GO (review m4). Efter 4.4 er
fortrydelse restore som i dag.

### 3.3 S4 i forslagswriteren

- Dublet-tjekket (`schema.sql:3649-3653`) udvides fra samme batch til **enhver** eksisterende
  `interpretation_proposal`-event for posten **i samme kilde** — joinet over
  `reimport_batch.source_id`, fordi `reimport_event` ikke bærer `source_id`, og `record_key` kun
  er unik pr. kilde (review m1) (`REIMPORT_WRITER_INTERPRETATION_PROPOSAL_EXISTS`). Dry-run ruller
  tilbage og efterlader ingen events, så dry-run → apply rammer ikke tjekket.
  Genudtræk forbliver trin 6, som spec'en siger; indtil da er en ny kørsel for en post med
  forslag et STOP, ikke en stille dublet.
- Forslagswriteren slår citerede ordinaler op **i det aktuelle sæt**
  (`clause_observation_current`), også i FOREIGN_POST-sonden (`schema.sql:3704-3708`). Et citat af
  en ordinal, der kun findes i et afløst sæt, er `REIMPORT_WRITER_CLAUSE_UNKNOWN`. Payloadens `verbatim_sha256` pr. citat kontrolleres som i
  dag mod den aktuelle klausul.
- Dispositionsoverskrivningen (`schema.sql:3766-3780`) kræver allerede, at den forrige er
  maskinel; med dublet-tjekket kan en anden forslags-kørsel ikke nå den. Uændret.

### 3.4 Invarianterne i nye, selvstændige triggere (review R2, MAJOR)

`db-migrations.sql` definerer `validate_clause_observation`, `validate_clause_disposition` og
`write_interpretation_proposal` flere gange (fx linje 17515, 17607, 18509). En fuld kørsel af filen
– prod-proceduren – genskaber derfor kortvarigt de gamle kroppe, og afbrydes den undervejs, bliver
de stående. Den gamle forslagswriter slår en ordinal op uden `STRICT` og uden sæt-filter og kan
knytte et forslag til en erstattet klausul med samme tekst. Så er noget skrevet forkert i prod.

Derfor ligger de nye invarianter **ikke** i de eksisterende funktioner, men i nye triggerfunktioner
med navne, som ingen historisk blok bruger:
- `trg_interpretation_observation_current_clause` (BEFORE INSERT på `interpretation_observation`)
  afviser et link til en klausul uden for det aktuelle sæt;
- `trg_clause_disposition_set_rule` (BEFORE INSERT på `clause_disposition`) håndhæver
  `erstattet`-reglen fra §3.2;
- `trg_source_observation_clause_set` (BEFORE INSERT) håndhæver `clause_set_seq`-reglerne fra §3.1,
  plus den udskudte tæthedstrigger.

Ændringerne i writerne (sæt-filter, S4) er en ekstra kontrol oven på triggerne, ikke den eneste.
`db-verify.sql` og prod-preflighten tjekker, at den aktive `write_interpretation_proposal` indeholder
`clause_observation_current`, efter samme mønster som `db-verify.sql:261`.

### 3.5 Læsere, der skal gå gennem det aktuelle sæt

Alle læsere af klausuler findes med `git grep "parent_observation_id\|clause_ordinal"`:
`write_interpretation_proposal`, `clause_evidence_projection.sql` (+ anon-projektionen),
`interpretation_proposal_projection.sql`, `interpretation_control_rows.sql`,
`export_43b_runner_input.R`, `export_clause_source_texts.R`, `export_clause_evidence_preview.R`,
`export_model_eligibility.R`, `compare_interpretation_proposal_projection.py` (nøgler på
`(record_key, clause_ordinal)` og tager højeste dispositionsversion — ufiltreret ville den vælge
den erstattede klausul og give `LINK_DRIFT`, review m2), `db-verify.sql`. Hver skifter til
`clause_observation_current` eller filtrerer eksplicit på sættet.

**Værn mod en glemt læser:** en statisk CI-test afviser nye forekomster af det regulære udtryk
`observation_kind\s*=\s*'clause'`, `parent_observation_id` og `clause_ordinal` uden for en navngiven
tilladelsesliste (view, writere, projektioner, db-verify). Et glemt filter ville ellers vise to sæt side om side — tavst, fordi
ordinalerne 1..n findes i begge.

### 3.6 Operationens rør (review M5)

`clause_revision` / præfiks `clause-revision:` / tællenøgle `clause_revisions` skal ind alle steder,
`clause_evidence` står i dag:
- `reimport_event_operation_check` (via den eksisterende union-hjælper i `db-migrations.sql`);
- `validate_reimport_authorization_payload`: nøglesæt, antal nøgler (`NOT IN (2,3,4,5)` → 2-6),
  præfiks-regex og antalskontrol (`schema.sql:2966-2982`);
- `red_finalize_reimport`'s optælling (`3810-3817`);
- `red_reimport_batch_result`: nøgleliste, præfikser og `event.operation IN (…)` (`3884-3905`) —
  mangler den, fanges en `clause_revision`-event uden for autorisationen ikke;
- `apply_reimport_helpers.R` (tællenøgler, `dependency_class`, dry-run/apply-gren, linje 36-73,
  166-170, 280);
- ACL i `db-rls.sql` (REVOKE-listerne ved 1253-1255 for det nye view, triggerfunktionerne og
  `clause_set_sha256`) og i `schema.sql:4389-4392`, plus `red_*`-vagtens liste;
- `reimport_profile.py` (profilskema og validator for revisionsprofilen, linje 39 og 220-263);
- `compare_interpretation_proposal_projection.py:128` (tællenøgler);
- `tests/sql/inspect-reimport-writer-catalog.sql` og `tests/testthat/test-apply-reimport.R`.

### 3.7 Manifest, profil og projektion

- **Profil:** `daa-2018-20-clause-revision-v1` (reimport-profil) binder regelversion
  `clause-rules-2018-20-v3`, den afledte `segmenter_version` fra ledgeren (P4) og
  `observation_extraction_method = clause_segment_v1` (klausul-triggeren kræver præfikset).
- **Manifest-builder:** `build_clause_evidence_manifest.py` får en `revision`-tilstand, der kun
  tager poster, hvis `clause_set_sha256` ændres, og som læser det gamle sæts seq og hash fra
  projektionen af det aktuelle prod-dump (ikke fra en fil). Forventet: `clause_revisions = 51`.
- **Projektion og komparator (review M4):** den eksisterende komparator kan ikke afstemme en
  revision — den afviser poster, der har klausuler i forvejen (`CLAUSE_PROJECTION_PREEXISTING`),
  kræver `dependency_class = clause_evidence`, præfikset `clause-evidence:`, et lukket rækkefelt-
  sæt og `disposition_version = 1`, og projektionens events dækker kun
  `operation = 'clause_evidence'`. Begge får en revisionstilstand: pr. revideret post er det gamle
  sæt uændret med én ny version `erstattet`, det nye sæt matcher manifestet med version 1, eventen
  er `clause_revision` med før- og efter-hash; alle andre poster og alle ikke-klausulrækker er
  uændrede. `clause_set_seq` og `clause_set_sha256` føjes til projektionens klausulrække.
- **Hashbaseline (review m3):** kolonnen ændrer `row_sha256 = sha256(c::text)` for *alle*
  observationsrækker. Projektioner fra før DDL'en (4.1c-kvitteringer, 4.4's GO-baselines) kan
  derfor ikke sammenlignes med projektioner efter. Før-snapshottet til revisionen tages **efter**
  DDL'en, og 4.4's GO-pakke skal alligevel bindes igen (beslutning 2026-09-23).

## 4. Gate og rækkefølge

1. DDL (kolonne, indeks, trigger, view, vokabular, operation-CHECK, writer, RPC, ACL/RLS +
   `red_*`-vagtens liste) som idempotent migration; `schema.sql` opdateres i samme ændring (S3).
2. Tests: SQL-test for writeren (positiv, hver afvisning, fortrydelse via ny revision,
   append-only intakt), S4-test (andet batch for samme post ⇒ afvist), læser-test (to sæt ⇒ kun
   det aktuelle ses), den statiske CI-vagt.
3. **Rehearsal mod et frisk prod-dump** (prod har 0 fortolkninger, så alle 42 kan revideres; den
   bundne restore `daa43b_…` har 4.3b's 84 forslag og ville — korrekt — afvise dem):
   DDL → før-snapshot → dry-run → apply → projektion `match` (51) → 0 kanonisk delta → `anon` uændret → fortrydelses-
   revision → frem igen.
4. Prod: gate for privat lag uden kanonisk delta (runbook, backup, rehearsal, GO). DDL'en er
   `anon`-neutral, men RLS/ACL-ændringer ⇒ uafhængigt review efter budgettet.
5. Derefter piloten om for de 32 poster mod en ny restore (alle sendes igen; pilotens cache er
   kontrakt 1.0) og kontrolmodellen på de nye forslag; så 4.4+4.5 i prod.

## 5. Åbne punkter (5.1-5.3 afgjort ved GO 2026-09-27 efter anbefalingen)

1. **`clause_set_seq` på rækken vs. en `clause_set`-tabel.** Udkastet vælger kolonnen (mindst
   DDL). En tabel giver et sted til sættets proveniens (regelversion, segmenter, batch), som i
   dag kun står i `reimport_event`.
2. **Skal 1939 kunne bruge operationen?** Den er udgaveneutral, men 1939's klausuler findes
   ikke endnu (trin 6); ingen 1939-specifik kode.
3. **Den statiske læser-vagt** kan give falske alarmer i dokumentation/tests; tilladelseslisten
   skal holdes smal.
4. **Forslagsnøglen er sæt-agnostisk** (`interpretation_proposal_key_material`: ordinaler og
   værdi). Intet problem nu; trin 6's genudtræk kræver en nøgleversion, der inkluderer sættet
   (review m5).

## 6. Plan-review runde 1 (2026-09-27, uafhængig agent, ikke Codex)

NO-GO: 1 BLOCKER, 5 MAJOR, 6 MINOR. Alle efterprøvet i koden før indarbejdning; M3's
flag-scenarie målt mod prod-teksterne (9 poster kun flag, 6 med ny startdisposition).

| Fund | Indarbejdet |
| --- | --- |
| B1 default skrives i alle rækker | §3.1: nullable uden default, `NULL = sæt 1` |
| M1 historisk indeksblok genskaber gammel unikhed | §3.1: samme indeksnavn, betinget drop/genskab |
| M2 »præcis max+1« bryder sæt med flere klausuler | §3.1: max+1 eller samme kørsel + udskudt tæthedstjek |
| M3 ledger-hash kan ikke genberegnes og ser ikke flag | §3.1: `clause_set_sha256`; §1/§3.6: 51 poster |
| M4 komparatoren kan ikke afstemme en revision | §3.7: revisionstilstand i projektion og komparator |
| M5 operationens rør mangler | §3.6 |
| m1 S4 uden kilde-afgrænsning | §3.3 |
| m2 oversete læsere, svagt mønster | §3.5 |
| m3 DDL ændrer rækkehashes | §3.7 |
| m4 fortrydelse og terminal `erstattet` | §3.2 |
| m5 sæt-agnostisk forslagsnøgle | §5.4 |
| m6 låserækkefølge | §3.2 |


## 7. Plan-review runde 2 (2026-09-27, uafhængig agent, sidste runde i budgettet)

GO med rettelser. Runde 1's rettelser er efterprøvet og holder. Nye fund:

| Fund | Indarbejdet |
| --- | --- |
| **MAJOR:** historiske migrationsblokke genskaber de gamle funktionskroppe, så invarianterne kan forsvinde, og den gamle forslagswriter kan knytte et forslag til en erstattet klausul | §3.4: nye, selvstændigt navngivne triggere + db-verify-tjek |
| §3.2 modsagde sig selv om `erstattet` | §3.2: præcis regel |
| Race med en fremtidig dispositionsflade | §3.2: `FOR UPDATE` på det aktuelle sæt før kontrollerne |
| Udskudt tæthedstjek kører ikke i dry-run | §3.1: `SET CONSTRAINTS … IMMEDIATE` |
| Ny post: `max` er NULL | §3.1: `coalesce(max,0)+1` |
| Kanonisk form af `clause_set_sha256` | §3.1: navngivet SQL-funktion, Python-parametre, sorterede flag, felt-mapping |
| Forkert fejlkode for citat af afløst sæt | §3.3: FOREIGN_POST-sonden ser kun det aktuelle sæt |
| Rørlisten ufuldstændig | §3.6 |
| Indeksskift uden `--single-transaction` | §3.1: ét `DO`-blok med midlertidigt navn |

## 8. Kodereview runde 1 (2026-09-27, uafhængig agent, ikke Codex)

GO. Syv MINOR-fund, hvert efterprøvet i koden før rettelse:

| Fund | Håndtering |
| --- | --- |
| Sæt-reglen for dispositioner læste "aktuelt sæt", før rækkelåsen blev taget (den fyrer før `validate_clause_disposition`) | `FOR UPDATE` på klausulrækken som første sætning; katalogtjek i `test-clause-set` t1 |
| Ingen writer-test reviderede et NULL-sæt 1 (prods form) | `test-clause-revision` t7; mutation (NULL-blind `erstattet`-løkke) fanges |
| S4 havde ingen CI-dækning | `test-clause-revision` t8; mutation (vagten fjernet) fanges |
| `write_clause_evidence` kaldte ikke `SET CONSTRAINTS … IMMEDIATE` som §3.1 siger | Tilføjet; katalogtjek i t1 |
| Indeksbytningen kender kun navnet `ux_source_observation_clause_ordinal` | Den levende `db-verify` kræver præcis ét ordinal-indeks, og at det er pr. sæt; mutation fanges |
| Revisionsvagterne dækker kun fortolkningslinks og menneskelige dispositioner. `source_mention`, `source_observation_text` og placement-kolonnerne (`basis_observation_id`, `header_observation_id`) kan pege på klausulrækker uden vagt | **Kendt grænse.** Ingen writer knytter dem til klausuler i dag. Vagten skal tilføjes, før den første gør det (sandsynligvis 5c placement) |
| Den statiske læservagt undtager `schema.sql`, `db-migrations.sql` og `db-verify.sql` helt | **Bevidst.** SQL-læsere dækkes af SQL-testene; en ny SQL-læser skal gå gennem `private.clause_observation_current` |
