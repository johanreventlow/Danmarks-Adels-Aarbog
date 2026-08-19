# DAA 1939 v50 fase B (narrativ-erstatning) — production readiness

Dato: 2026-08-19. Scope: fase B af den evidensbaserede 1939 v50-genimport —
erstatning af de **551** kanoniske 1939-biografitekster med den
menneskeverificerede Calamari-tekst, normaliseret med `narrative_norm_v1`, plus
publicering af **543** nye record-bindinger. Ingen production apply og ingen DDL
er udført i dette trin; pakken indeholder transform, bygger, konverter, writer,
tests og en gennemført rehearsal mod en frisk restore af et umiddelbart
prod-dump.

## Konklusion

**GO for at forberede én fremtidig, eksplicit autoriseret production-apply** af
fase B's 551 narrativ-upserts og 543 binding-publiceringer. Transformen er ren,
versioneret og korpus-regressionstestet; manifestet er deterministisk bygget og
hash-låst mod brugerens egen afgørelsesfil; writeren er hard-låst til fase B's
tællekontrakt (551/551/0/543/8/2) og kører alt i ÉN transaktion; en rehearsal mod
en produktionsækvivalent restore har produceret præcis de forventede deltaer med
nul kanonisk delta og bevist at replay afvises fail-closed.

Production-status er fortsat **NO-GO**, indtil brugeren særskilt har godkendt
apply med de eksakte hashes og identiteter i afsnittet
[Gates og krævet godkendelse](#gates-og-krævet-godkendelse). Manifestet bærer
selv `production_authorized: false` og `apply_gate: "NO-GO"`.

To gates skiller sig ud og skal lukkes **før** godkendelsen indhentes:

1. en **ny umiddelbar backup** af produktionen, og
2. en **read-only prod-probe af SQL-`digest()`-opløsning** — fase A brugte
   udelukkende R-side `digest::digest()`, så denne writers rå SQL-`digest()` er
   aldrig afprøvet mod produktionen. Lokalt krævede den `search_path` med
   `extensions`.

## Hvad pakken ændrer

- **551 narrativer** (`narrative.tekst` for kilde 3 = DAA 1939) erstattes af den
  normaliserede Calamari-tekst: 543 eksisterende personer fra fase A-manifestet
  + de 8 personer, task 25 oprettede. Kaldsvej: 551× `red_upsert_narrativ`
  (`p_privat = false`, `p_side = page_from::text`). Alle 551 findes → 551 UPDATE,
  0 INSERT; narrative-antallet for kilde 3 forbliver 577.
- **543 record-bindinger publiceres** via `red_publicer_narrative_record`
  (ny-publiceringsvejen, `record_label = source_record_key`,
  `citation_label = 'DAA 1939 side ' || page_from`). De 8 eksisterende bindinger
  røres **ikke** — et genkald ville fejle `ALREADY_BOUND`. Tabellen går fra 8 til
  551 published rækker.
- **2 dokumenterede side-rettelser** som følgevirkning af upserten: person 975
  `508 → 509` og person 986 `503 → 505`. Se
  [Side-rettelserne](#side-rettelserne-de-eneste-skrivninger-uden-for-narrativteksten).
- **Nul kanonisk delta i øvrigt.** Ingen person, fact, assertion, conclusion,
  relation, family, family_member, citation, cache eller `private.*`-evidens
  ændres. Verbatim, spans og rendition er urørte — kun `narrative.tekst` (og de to
  `narrative.side`-værdier) skrives.
- **De 26 narrativer uden for scope** (577 − 551) røres ikke. Profil:
  18 `samme_som`-aliaser, 6 staged upromoverede, 2 malformede legacy-rækker.
  I manifestet bærer alle 26 den ensartede maskinlæsbare årsag
  `no_mapped_source_record` (profilen 18/6/2 er kun dokumenteret i prosa —
  se forbehold 6).

## Autoritative artefakter

Alle værdier nedenfor er **målt** i denne pakke med `shasum -a 256` mod filerne på
disk, medmindre andet er anført.

| Artefakt | Rolle | SHA-256 | Status |
|---|---|---|---|
| `narrative-replacement-manifest-v2.json` (**fil-byte**) | CLI'ens `--manifest-sha256` | `9145cf38d2cefcbe5e3ec6e8429181f8448c3bdcfead855a3a28f577188bdda0` | målt ✅ |
| manifest **content** (`manifest_content_sha256`) | kanonisk indholdsidentitet, genberegnet af R-validatoren | `5179e9f5fa1d319819d2afd7569b759361684375701c4a92b7037e4a6527e919` | målt ✅ |
| `narrative-replacement-decisions-v1.json` | brugerens 178 afgørelser; pinnet som `input_hashes.decisions_sha256` | `4090680b0fc9cb2c590b2235606536557d0c4dd7afebe5cc6e34b415334e5f0b` | målt ✅ |
| `phase-a-anchor-manifest-v1.json` | tekstkilde for de 543 | `1945416b3b56e781787366008a2463b419cb8ed4df3ef1399211cac5c999e208` | målt ✅ |
| `production-write-manifest-v1.json` (task 25) | tekstkilde for de 8 | `8417b6deeaf32b3cf39a4f2995a06211f8368172dfa97a188e03c6f7ef379a1f` | målt ✅ |
| `narrative-publication-manifest-v1.json` | de 8 eksisterende bindinger | `d71908cf3a998d57602a91d936a2c1b19cf874da938bdef0d691fda9a2ac7654` | målt ✅ |
| `full_ocr_calamari_r6_clean.txt` | rendition + bindestregs-korpus | `020123a3588dacf80705a22fb021ab4f5da97b8de202e8664304ca01f9a6da37` | målt ✅ |
| `narrative-old-sha-export-v2.json` | 577 gamle narrativ-SHA'er + `side` + `privat` | `ec9845e0504d77980182617afd9f1b7daddb447d12e55dd4f6148c435987fec6` | målt ✅ |
| `narrative-replacement-flags-v1.json` | de 178 flags fremlagt for brugeren | `707e993fa73aebb626bebe1414f3e6e4c7f790cc357556d29bf437be50d5d47e` | målt ✅ |
| `narrative-afgoerelser.txt` — **brugerens redigerede** token-fil | menneskeligt input til afgørelserne | `18487a2b437269695cabb6ee555ccf730add708e1940ec3720f562cb16e3ae77` | **kun påstået** ⚠️ — se nedenfor |
| `narrative-afgoerelser.txt` — filen der ligger på disk nu | regenereret **før**-redigering-udgave | `3566f59f2c2f087f71a19ac99f77cdd053eb25e0cd14c114494be3e1d05a3d50` | målt ✅ |

Alle seks input-hashes er pinnet i manifestets `input_hashes` og er verificeret
identiske med de målte filbytes. Manifestet ligger under ignoreret `work/` og
committes ikke. Ingen `work/`-artefakt er del af denne commit.

### KRITISK: de to manifest-hashes har hver sin rolle

Som i fase A må de to ikke forveksles i godkendelsen:

- **Fil-byte-SHA `9145cf38…`** er integritetstjekket på selve filen; det er denne
  værdi, CLI'ens `--manifest-sha256` verificerer (writeren læser filens rå bytes
  og hasher dem, før JSON overhovedet parses).
- **Content-SHA `5179e9f5…`** er feltet `manifest_content_sha256` *inde i*
  manifestet; R-validatoren genberegner den kanoniske serialisering og
  sammenligner. Til forskel fra fase A er der **ingen** batch-tabel, der lagrer
  content-SHA'en — fase B har ikke idempotens via batch-genbrug. Se
  [Replay](#replay-er-fail-closed-ikke-idempotent).

### ⚠️ Uoverensstemmelse: to menneskevendte Task 3-artefakter er overskrevet

`narrative-afgoerelser.txt` på disk hasher til `3566f59f…`, **ikke** til den
`18487a2b…`, som ledgeren tilskriver brugerens redigerede fil. Filen på disk er
den uredigerede udgave: den indeholder **0 `[STRIP]`-tokens**, mens
afgørelsesfilen indeholder 2 `strip`. Filstemplet er 19. aug. 12:52 — *efter* at
`narrative-replacement-decisions-v1.json` blev skrevet (12:24). Filen er altså
regenereret oven i brugerens redigerede udgave, og `18487a2b…` findes ikke
længere nogen steder på disken (eftersøgt). Det samme gælder reviewarket
`narrative-replacement-review.md`: ledgeren noterer `f743d8b1…`, disken har
`d782e8ef…` (stemplet 12:53).

**Blokerer det?** Nej. Den autoritative optegnelse over brugerens beslutning er
`narrative-replacement-decisions-v1.json` (`4090680b…`), som er målt intakt og er
kryptografisk bundet ind i manifestet, som writeren igen verificerer. Kæden
*manifest ← decisions* er lukket. Det tabte er kun den menneskelæsbare
inputformular.

**Genverifikationsvej for brugeren:** afgørelsesfilen er en flad
`flag-id → action`-tabel (flag-id = `record_key:char_offset:kind`), så alle 178
valg kan læses og bekræftes direkte i JSON-filen uden token-filen.

## Transformens totaler og flag-håndtering

`narrative_norm_v1` er en ren, deterministisk funktion uden I/O. Målt over det
rigtige 551-scope og **låst som asserts** i
`test_normalize_narrative_1939_v50.py` (32/32 grøn ved HEAD `df66966`):

| Regel | Total |
|---|---|
| Bløde ombrydninger sammenføjet (`soft_breaks_joined`) | 2304 |
| Orddelinger sammentrukket (`hyphens_merged`) | 584 |
| Bindestreg bevaret som kompositum (`hyphens_kept_compound`) | 10 |
| Søskende-ordenstal strippet (`ordinal_stripped`) | 499 |
| `### PAGE`-markørblokke fjernet (`page_markers_removed`) | 73 |

Slutinvarianter håndhæves i funktionen: intet `### PAGE` i outputtet, intet
enligt `\n` (web-fladen renderer `\n` som linjeskift), ingen trailing whitespace.

**Flags: 178, alle menneskeligt afgjort.**

| Flag-art | Antal | Betydning |
|---|---|---|
| `hyphen_unproven` | 168 | sammentrækning uden korpus-evidens for den ubrudte form |
| `hyphen_ambiguous` | 8 | både/hverken form findes i korpus + stort bogstav efter bindestreg |
| `ordinal_ambiguous` | 2 | ordenstal uden punktum / med parentes |

Brugerens afgørelser (målt i `decisions-v1`): **165 `merge` / 11 `keep` /
2 `strip`**. Byggeren afviser fail-closed at fryse et manifest, hvis der er
uafgjorte flags; det frosne manifest har `flags: []` (0 restflags).

Til reference: transformens rå defaults var 168 `merge` / 10 `keep` (0 `strip`).
Brugeren afveg altså fra defaulten på **5** flags — 3 sammentrækninger vetoet til
`keep` (heraf én entydig OCR-korruption, som var forhåndsanbefalet til `keep` i
det ark, brugeren fik) og **begge** ordenstal til `strip`. Fase B foretager
principielt **ingen redaktionelle OCR-rettelser**: et fejlagtigt sammensat ord kan
kun vetoes til den delte form, ikke rettes — egentlig tekstrettelse er senere
redaktørarbejde. Fordelingen 165/11/2 kan ikke fuldt ud rekonstrueres mod
brugerens egen redigerede token-fil, da den er overskrevet (se uoverensstemmelsen
ovenfor); den er derimod målt direkte i den hash-låste afgørelsesfil.

## Rehearsal mod frisk produktionsækvivalent restore

Kørt i `daa1939_phase_b_rehearsal1` — en frisk restore af et umiddelbart prod-dump
taget med det allow-listede backup-script (kun `DEST`-linjen ændret):
`daa-local-phase-b-rehearsal-20260819-132105.dump`, mode 600, 5.570.058 bytes,
sha256 `f17f2f72117fdba8f9b32068541a9bb644bd880a7a7000142f0d1580772e32e5`,
1659 katalogposter. Lokal PostgreSQL 17, cluster-id `7657242220770903427` — en
anden identitet end produktionen. Fuld rapport med alle kommandoer:
`work/task25-1939-v50-production-writer/phase-b-rehearsal-report.md` (ignoreret
`work/`, ikke committet).

Kontroltal efter restore matchede eksakt: `person` 1812, kilde-3-`narrative` 577,
`private.narrative_record_publication` 8 (alle `published`),
`private.source_record` 592, fase A-batch `328a813a-3c04-4265-8263-79ba3b2a0715`
i status `finalized`.

| Trin | Resultat |
|---|---|
| **Dry-run** | exit 0, `committed=false`; baseline før/efter **byte-identisk** → nul persistens |
| **Apply** | exit 0, `committed=true`, `narratives_updated=551`, `bindings_published=551` (tabel-bredt tal efter apply = 8 eksisterende + 543 nye) |
| **Replay** | **afvist fail-closed**: `OLD_SHA_MISMATCH:924`, ingen ændringer |

### Efterkontrol efter apply

- 551/551 tekster matcher manifestets `normalized_sha256` eksakt.
- De 26 uden for scope: 26/26 uændrede (0 rørt).
- Kilde-3-narrative-antal fortsat 577 → 0 INSERT, som kontrakten kræver.
- `privat = true` blandt de 551: 0.
- Side-rettelserne gennemført: person 975 → 509, person 986 → 505.
- Kanoniske tællinger uændrede: `person` 1812, `fact` 7199, `relation` 2031,
  `family` 682, `family_member` 2258.
- Bindinger: 551 `published` i alt.
- **Ét** change_set for hele operationen (943 rækker efter, mod 942 før).

### Replay er fail-closed, ikke idempotent

Modsat fase A er `red_upsert_narrativ` ikke naturligt idempotent. Writerens
preflight verificerer derfor `expected_old_narrative_sha256` for hvert af de 551
narrativer mod DB, **før** noget skrives. Efter en gennemført apply matcher intet
længere, og en genkørsel afvises på det første afvigende id
(`OLD_SHA_MISMATCH:924`) uden at røre databasen. Det er den ønskede adfærd, ikke
en mangel — men det betyder også, at et utilsigtet gentaget `--apply` **ikke** er
harmløst-idempotent: det er en hård fejl, og en reel genkørsel efter apply kræver
et nyt manifest bygget på den nye tilstand.

### 550-vs-551: forklaret og harmløs

Change_set'et rummer **550** `narrative`-UPDATE-events, ikke 551. Person 1780's
1939-narrativ er teksten `(?)` (3 tegn), som normaliseringen lader uændret;
UPDATE'en blev derfor et no-op, og versioneringstriggeren skrev ingen
historik-post. Uafhængigt genmålt mod den efterladte rehearsal-base:
`change_event` for sættet = 550 rækker, alle `tabel='narrative'`, `op='UPDATE'`,
alle 550 med `foer` udfyldt. 56 af de 551 tekster er kortere end 40 tegn — ægte,
meget korte bogindførsler, ikke datafejl.

## Side-rettelserne (de eneste skrivninger uden for narrativteksten)

Første rehearsal-forsøg blev **blokeret fail-closed** af writerens privat/side-værn
(`SIDE_UNEXPECTED:975:observed=508:expected=509`); udvidet, læsende diagnostik
fandt præcis to afvigelser (975 og 986) og ingen andre. Undersøgelsen viste at
manifestet har ret: det menneskeverificerede grænsemateriale siger 509/505,
spans ligger under de tilsvarende PDF-sider, hver PDF-side mapper til præcis ét
trykt sidetal (0 konflikter i hele bogen), og andre personer på samme trykte side
har den korrekte værdi i DB. De to er gamle importfejl — netop den slags fase B
retter.

Kontrakten blev derfor udvidet i stedet for at blødgøre værnet (commit `df66966`):
manifestet **opregner** rettelserne i `side_corrections`, og writeren accepterer
kun præcis dem. Enhver ikke-opregnet afvigelse aborterer fortsat
(`SIDE_UNEXPECTED`), og en opregnet rettelse hvis `observed` ikke længere matcher
DB aborterer som `SIDE_CORRECTION_STALE` i stedet for at blive stiltiende sprunget
over.

```json
"side_corrections": [
  {"person_id": 975, "observed": "508", "expected": "509"},
  {"person_id": 986, "observed": "503", "expected": "505"}
]
```

Begge har `binding == "create"`, og deres `citation_label` er allerede afledt
korrekt af `page_from` (509/505) — der er derfor **ingen** parallel
"forkert citation_label"-mangel at lukke ovenpå. `narrative.side` indgår ikke i de
kanoniske tællinger, så "nul kanonisk delta" står uændret.

## Fortryd-vejen

Alle 551 upserts folder sammen til **ét** change_set, fordi de kører i én
transaktion. Fortryd er derfor **én** handling:

```sql
SELECT red_fortryd_change_set(<id>);
```

**Sådan finder operatøren `<id>`.** Writerens output-JSON rapporterer *ikke*
change_set-id'et (den udskriver `mode`, `committed`, `database_name`,
`system_identifier`, `narratives_updated`, `bindings_published`,
`canonical_counts`). Id'et findes read-only umiddelbart efter apply:

```sql
SELECT id, created_at, operation, summary
FROM change_set
WHERE operation = 'red_upsert_narrativ'
ORDER BY id DESC LIMIT 1;
```

Bemærk at sættets `summary` kun navngiver den **første** person i batchen
(i rehearsalen: «Opdaterede narrativ på person/924 (kilde 3)»), selv om det dækker
alle 551 — teksten må ikke læses som om sættet kun rørte én person. Bemærk også,
at `change_set.id` ikke er tætpakket: rehearsal-basen havde 943 rækker med
maks-id 952. **Antal ≠ id.**

**Hvad en fortrydelse gør.** `red_fortryd_change_set` åbner et reversal-sæt
(`operation='fortryd'`, `reverterer_id` = det oprindelige id), går sættets events
igennem i omvendt `seq`-orden og genskaber for hver UPDATE hele `foer`-rækken via
`_version_upsert_row` — altså både den gamle `tekst` og den gamle `side`. Den er
optimistisk låst: hvis en nyere ændring har rørt en af rækkerne, afvises
fortrydelsen (`nyere ændring rører …`), medmindre `p_force => true` gives bevidst.
Bagefter regenereres afledte projektioner (`regen_person_visning`,
`_regen_mentions_for('narrative', …)`) én gang.

**Tre forbehold ved fortrydelsen — læs dem før apply:**

1. **Person 1780 kommer ikke med.** Kun 550 af de 551 har en historik-post; den
   551. var et no-op, så der er intet at genskabe (og heller ikke noget tab).
2. **De 543 nye bindinger fortrydes IKKE.**
   `private.narrative_record_publication` står hverken i `version_pk_registry`
   eller har en versioneringstrigger (verificeret mod rehearsal-basen), så
   change_set'et indeholder ingen binding-events. En fortrydelse ruller teksterne
   tilbage, men efterlader de 543 `published` bindinger. At fjerne dem igen er en
   særskilt, manuel operation.
3. **Gamle tekster er bevaret i `change_event.foer`** som hele rækker — verificeret
   i rehearsalen: 550/550 events har `foer` udfyldt med `tekst`. De er også
   fremsøgelige pr. person via `hist_for_subjekt('narrative', <narrative_id>)`.

## Frisk verifikation

Alle tal nedenfor er **kørt af denne pakke** ved HEAD `df66966`.

| Suite | Resultat |
|---|---|
| `test_normalize_narrative_1939_v50.py` | **32 passed** (inkl. korpus-regression mod det rigtige 551-scope) |
| `test_build_narrative_replacement_manifest_1939_v50.py` | **54 passed** — ⚠️ se note nedenfor |
| `test_convert_narrative_decisions_1939_v50.py` | **17 passed** |
| `test_apply_narrative_replacement_1939_v50.R` (writer, DB-fri) | **PASS 160 assertions** |
| `test_export_narrative_old_sha_1939_v50.R` | **PASS 35 assertions** |
| `Rscript run-tests.R` (hele R-suiten) | **FAIL 0 \| WARN 5 \| SKIP 2 \| PASS 815** |
| `pytest -q` (hele pipeline-suiten) | **1835 passed, 3 skipped** |

WARN 5 / SKIP 2 er præeksisterende og urelaterede (samme benigne
`--file=`-detektionsadvarsel og lokal-DB-smoke-skips som i fase A).

⚠️ **Uoverensstemmelse (tal, ikke rødt):** ledgeren og opgavebriefen angiver
"bygger 81" for manifest-byggerens testfil. Målt ved HEAD er tallet **54**
(54 collected, 54 passed). Kontrakt-fix-rapporten angiver selv "54, op fra 33 før
v2-ombygningen", hvilket heller ikke kan forenes med 81. Ved commit `bfa145e`
(pre-v2) havde filen 49 `def test`-funktioner. Tallet 81 er altså et stale eller
anderledes optalt tal og bør ikke bruges i godkendelsen; **54** er den målte
sandhed ved den kode, der skal køre.

**Credentialscan** over alle 16 nye/ændrede filer i pakken (12 scripts/tests i
`.claude/skills/daa-extract/scripts/`, 2 testthat-wrappere, 2 plandokumenter) med
mønstrene `eyJ…` / `postgres://…:…@` / `service_role` / `sb_secret` /
`password=`: **0 hits** i alle 16 filer. Samme scan over dette readiness-dokument
giver 2 hits, som begge er selve mønsternavnene i denne sætning — ingen
credentials.

`git diff --check`: **grøn** (exit 0).

Ingen verbatim biografitekst, personkontekst eller `work/`-indhold er gengivet i
dette dokument eller i pakkens kode — kun tælle-, hash- og strukturkontrol samt
person-id'er (invariant 8).

## Kendte noter og forbehold

1. **Rehearsal-basen er en prod-restore, ikke produktionen.** Alle tal i
   [Rehearsal](#rehearsal-mod-frisk-produktionsækvivalent-restore) er målt i
   `daa1939_phase_b_rehearsal1` (cluster `7657242220770903427`). Restoren er taget
   umiddelbart før, og de gamle narrativ-SHA'er er separat verificeret
   byte-identiske med produktionens (aggregat `286594d0…` over alle 577, plus
   direkte stikprøve). Writerens preflight er dog stadig det sidste og afgørende
   værn: afviger ét eneste af de 551 old-SHA'er i prod, aborterer kørslen
   fail-closed uden at skrive.
2. **SQL-`digest()` er uafprøvet mod prod.** Se
   [gate 2](#gates-og-krævet-godkendelse). Bemærk asymmetrien: eksport-scriptet
   bruger Postgres' indbyggede `sha256(convert_to(…,'UTF8'))` uden
   pgcrypto-afhængighed, mens writeren sender ukvalificeret
   `encode(digest(convert_to(n.tekst,'UTF8'),'sha256'),'hex')` som rå SQL uden om
   enhver `SECURITY DEFINER`-funktion — så `schema.sql`s `search_path`-varianter
   hjælper ikke her.
3. **Forbindelsen skal være session-mode.** `set_config('request.jwt.claim.sub',…)`
   kaldes uden for transaktionen; en transaction-mode-pooler ville tabe aktøren.
4. **Bindingstjekket er tabel-bredt** (8 før / 551 efter), ikke scoped til de 551
   narrative_id'er. Det er bevidst — det fanger fremmede bindinger — men det
   betyder, at enhver anden binding oprettet i mellemtiden vil få preflight eller
   verify til at fejle.
5. **`narrative-publication-backup.sh`s `DEST`-linje peger p.t. på
   rehearsal-navnet** (`daa-local-phase-b-rehearsal-…`), fordi Task 5 redigerede
   den. Den skal sættes tilbage til et apply-navn, før pre-apply-backuppen tages,
   ellers navngives backuppen misvisende.

**Parkerede minors fra task-reviewene** (ingen af dem er datarisici; alle er
fail-closed eller rent diagnostiske):

| # | Fund | Konsekvens |
|---|---|---|
| T2-M2 | `source_record_key`-disjunkthed mellem de 543 og de 8 bindinger er ikke asserteret i byggeren | Snittet er empirisk tomt i dag (verificeret). Manglende assert, ikke fejl. |
| T2-M3 | `ManifestError` slipper ud af byggerens `main()` som traceback | Adfærd er fail-closed; exit-kontrakten er 0 = manifest skrevet, 2 = flags skrevet/manifest afvist, 1 = abort. |
| T2-M4 | Byggeren kræver `expected_status == "draft"` i publikationsmanifestet, mens DB'ens 8 rækker i dag er `published` | Inert for denne apply (det frosne manifest er bygget mod den eksisterende fil). Rammer kun en **fremtidig genopbygning** af manifestet mod nuværende DB-tilstand. |
| T2-M5 | `out_of_scope.reason` er ensartet `no_mapped_source_record` | Profilen 18 aliaser / 6 staged / 2 malformede findes kun i prosa, ikke maskinlæsbart i JSON'en. |
| T4-M2 | `NARRATIVE_MISSING:<person_id>` er uopnåelig — generisk `PREFLIGHT_COUNT_INVALID` fyrer først | Ved et manglende narrativ får operatøren "antallet passer ikke" i stedet for et person_id. Diagnostik, ikke spec-brud; SHA-afvigelse rapporterer korrekt person_id. |
| T4-M3 | En fejlet `commit` kan få sin årsag maskeret af en sekundær rollback-fejl | Ingen datarisiko (en fejlet commit er ikke committet), men apply-rapporten kan vise en vildledende årsag. |
| T4-M5 | `vapply(…, integer(1))` antager at jsonlite giver `integer` | Verificeret empirisk for det ægte, frosne manifest (alle 551 `person_id`/`page_from` er `integer`). Et regenereret manifest med `924.0` ville dø med en R-typefejl i stedet for en domænefejl. Fail-closed. |

## Gates og krævet godkendelse

Stoptilstande i den nuværende kæde: forkert manifest-fil-byte-hash, drevet
input-hash (alle seks), content-hash-afvigelse, `counts`/`arithmetic`-afvigelse
(551/551/0/543/8/2), forkert schema-version (v1 afvises), manglende eller dobbelt
tilstandsflag på CLI'en, manglende `redaktion`-aktør, `privat = true` på nogen af
de 551, ikke-opregnet eller forældet `side`-afvigelse, old-SHA-drift på ét eneste
narrativ, forkert antal bindinger før eller efter, samt en ikke-`finalized`
fase A-batch.

Før en production apply skal **alle seks punkter** være navngivet i en eksplicit
brugergodkendelse. Indtil da er production apply **NO-GO**.

**1. Ny umiddelbar backup af produktionen.**
Tag den med det allow-listede backup-script (efter at `DEST`-linjen er sat til et
apply-navn, jf. forbehold 5) og navngiv i godkendelsen: **eksakt sti, mode `0600`,
bytestørrelse og SHA-256**. Rehearsal-dumpet `f17f2f72…` tæller **ikke** — det er
taget før rehearsalen og er nu timer gammelt.

**2. Read-only prod-probe af SQL-`digest()`-opløsning.**
Fase A brugte udelukkende R-side `digest::digest()` og har derfor aldrig lagt
SQL-niveau `digest()` på prøve mod produktionen. Denne writer gør. Proben skal
køres **som den rolle og over den forbindelse writeren selv bruger** (samme
`SUPABASE_*`/`PG*`-env, session-mode, `sslmode=require`), og med **ukvalificeret**
`digest` — en probe med eksplicit `SET search_path` eller som en anden rolle
beviser intet:

```sql
SELECT encode(digest(convert_to('x','UTF8'),'sha256'),'hex');
-- forventet: 2d711642b726b04401627ca9fbac32f5c8530fb1903cc4db02258717921a4881
```

*Hvis proben fejler* (`function digest(…) does not exist`): den rigtige vej er
**ikke** at køre `ALTER DATABASE … SET search_path … extensions` mod prod — det er
en konfigurationsskrivning, der kræver sin egen autorisation. Den rette vej er en
writer-rettelse (kvalificér til `extensions.digest`, eller skift til den
indbyggede `sha256(convert_to(…))`, som eksport-scriptet allerede bruger) **plus
en ny rehearsal**. Fase B er da NO-GO indtil det er gjort.

**3. Session-mode-forbindelse til produktionen.**
Supabase *Session pooler* (IPv4), `sslmode=require`, EU-region — ikke
transaction-mode. Produktionsdatabase `postgres`, system identifier
`7642734024280108049`. `DAA_REIMPORT_ACTOR_ID` skal være en **redaktions-profil**
(`profiles.rolle = 'redaktion'`) i produktionen.

**4. Manifest-hashes med roller.**
`--manifest-sha256` =
`9145cf38d2cefcbe5e3ec6e8429181f8448c3bdcfead855a3a28f577188bdda0` (fil-byte)
**og** `manifest_content_sha256` =
`5179e9f5fa1d319819d2afd7569b759361684375701c4a92b7037e4a6527e919` (kanonisk
indhold, genberegnet af R-validatoren) — begge, med hver sin rolle. Godkendelsen
bør desuden navngive afgørelsesfilen
`4090680b0fc9cb2c590b2235606536557d0c4dd7afebe5cc6e34b415334e5f0b`, som er den
kryptografiske binding til brugerens 178 valg.

**5. Præcis én `--apply`, ingen retry.**
Kommandoen kræver eksplicit `--dry-run` **eller** `--apply` (aldrig default).
Kør gerne `--dry-run` først — den er bevist nul-persistent. Kør derefter `--apply`
**én gang**. Replay er bevist fail-closed: et gentaget `--apply` afvises på
old-SHA-drift, men det er en hård fejl, ikke en idempotent no-op — så en
gentagelse må aldrig være en refleks. Bliver kørslen afbrudt undervejs, ruller
transaktionen tilbage; genoptagelse kræver en ny vurdering, ikke en blind
gentagelse.

**6. Read-only efterkontrol med samme tal som rehearsalen.**
- 551/551 narrativ-tekster matcher manifestets `normalized_sha256`.
- Kilde-3-narrative-antal uændret **577** (0 INSERT).
- `private.narrative_record_publication`: 8 → **551**, alle `published`.
- De 26 uden for scope: 26/26 uændrede.
- `privat = true` blandt de 551: **0**.
- Side-rettelser gennemført: person 975 → 509, person 986 → 505; ingen andre
  `side`-ændringer.
- Kanoniske tællinger **uændrede** — de fem, fase B's rehearsal faktisk målte:
  `person` 1812, `fact` 7199, `relation` 2031, `family` 682,
  `family_member` 2258. Ønskes bredere dækning (`assertion`, `citation`,
  `conclusion`, `person_external_id`), skal de måles **før** apply og
  sammenlignes med sig selv bagefter — fase A's tal for dem
  (9304/8582/9215/1168) er en ældre baseline fra en anden kørsel og må ikke
  bruges som forventningsværdi her, da en afvigelse så ikke kan skelnes fra
  almindelig drift siden fase A.
- Præcis **ét** nyt change_set med **550** `narrative`-UPDATE-events, alle med
  `foer` udfyldt — og id'et noteres i apply-rapporten som fortryd-nøgle.
