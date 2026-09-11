# Trin 4 · dagsværk 4.3a: model-runneren, svar-cachen og udelukkelseslisten — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `evidence_runner.py` kan kalde `gpt-5.6-terra` gennem `codex exec` for én record ad gangen, validere svaret mod en record-scoped claim-kontrakt, føre regnskab med reelt målt forbrug og stoppe fail-closed på hver fejltype — med en per-kald arbejdsmappe, der gør §19's »én record ad gangen« til en grænse i stedet for en henstilling, og en hash-bundet udelukkelsesliste, uden hvilken runneren nægter at køre.

**Architecture:** Et nyt motor-script `evidence_runner.py` med en injicerbar `run_codex`-søm (så tests aldrig starter Codex), en ny kontraktfil `references/evidence-claims-1.0.json` + `validate_record_claims` i `evidence_extract.py`, en ny promptfil `references/evidence-extract-prompt-1.0.0.md` skrevet til den record-scoped kontrakt, en per-record svar-cache, `BatchManifest` udvidet med fire felter, et R-eksportscript til udelukkelseslisten, og en profilbump til 2018-20 v1.3.0 med `pricing`.

**Tech Stack:** Python 3 + pytest, `codex exec` (codex-cli 0.153.4), R (DBI/RPostgres) til læse-kun eksport, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-06-trin4-fortolkningskaede-og-klausulgranularitet-design.md` §6 (runner), §9.2 (udelukkelse), §19 (én record ad gangen).

**Forudgående måling:** `docs/evidensbaseret-genimport/runner-usage-probe-147-4-3a.md` (forbrugsproben, 2026-09-11). Planen bygger på dens tal, ikke på skøn.

---

## Spec-afvigelser, der kræver projektejerens GO før kodning

Tre steder afviger denne plan fra den godkendte spec. Alle tre er fundet ved at **måle**, ikke ved at læse. De er planens vigtigste indhold, og de skal afgøres før Task 1.

### A. `--ignore-user-config` ind i §6.2's flagliste

§6.2 lister `--model --sandbox read-only --ephemeral --ignore-rules --json --output-schema` og stdin lukket. Proben viser, at `--ignore-rules` kun dækker execpolicy-filer: brugerens `~/.codex/AGENTS.md`, `config.toml` og tre brugerskills injiceres stadig i hvert kald og udgør **6.288 af de 21.554** input-tokens i et tomt kald.

Besparelsen er ikke argumentet. Argumentet er, at §6.2 hash-binder prompten (`prompt_sha256`) netop for at gøre et modelkald reproducerbart og efterprøveligt — men brugerens private AGENTS.md ligger uden for den hash og kan ændre sig mellem to kørsler, uden at noget i manifestet afspejler det. To kald, der ser identiske ud i manifestet, kan have vist modellen forskellig kontekst. **Uden dette flag er `prompt_sha256` en halv sandhed.**

**Forslag:** `--ignore-user-config` tilføjes til flaglisten, og runneren nægter at køre uden det.

### B. `extract-prompt.md` omdøbes ikke — der skrives en ny prompt

§6.2 siger, at »den eksisterende uversionerede `extract-prompt.md` omdøbes/versioneres som et skridt i 4.3a, så profilens `prompt_version` får en matchende fil«. Formuleringen bygger på en antagelse, der ikke holder ved eftersyn:

| Efterprøvet | Fund |
| --- | --- |
| Binder koden profilens `prompt_version` til en fil? | **Nej.** `prompt_version` er en ren streng, der bæres gennem `BatchManifest`. Ingen kode åbner en promptfil. |
| Er de to versioner i familie? | **Nej.** Profilen siger `evidence-extract-1.0.0`; filens egen header siger `prompt-version: 2026-07-29b`. |
| Passer promptens indhold til den nye kontrakt? | **Nej.** `extract-prompt.md` er den gamle skills trin ③-prompt: den instruerer modellen i at skrive `work/extracted/<linje>-<nr_label>.json` med Write-værktøjet og validere mod `extraction-schema.json`. Den kender hverken klausul-ordinaler, `evidence-claims-1.0` eller record-scoping. |
| Bruges den stadig? | **Ja** — `SKILL.md:104` peger på den som den frosne prompt for den manuelle trin ③-vej. |

En omdøbning ville altså give en fil, hvis navn lyver om dens indhold, og samtidig rive den gamle vej i stykker.

**Forslag:** `extract-prompt.md` forbliver urørt. 4.3a skriver en **ny** `references/evidence-extract-prompt-1.0.0.md` til den record-scoped kontrakt, og `load_profile` begynder at kræve, at filen for profilens `prompt_version` findes, og at hashe den. Dermed bliver `prompt_version` for første gang bundet til noget.

### C. §19 skal håndhæves af arbejdsmappen, ikke af prompten

Dette er den alvorligste af de tre. §19's »modellen ser én record ad gangen« er i dag en instruktion i prompten. Kanarietesten i proben viser, at det ikke er en grænse: en fil lagt uden for kaldets `-C`-mappe blev læst, fordi modellen **eksekverede en shell-kommando** (`/bin/zsh -lc "… sed -n '1,20p' ../canary/uden-for-cwd.txt"`) og gengav indholdet ordret.

`--sandbox read-only` forbyder skrivning og netværk, ikke kommandokørsel. `-C` sætter arbejdsmappen, ikke en læsegrænse. `codex exec` har ingen flag til at slå værktøjsbrugen fra (efterprøvet i `--help`).

Kører runneren et sted, hvorfra `work/`, `work_1939_stamtavle/`, restore-eksporten eller `~/.private/` kan nås, er prosa om levende personer inden for rækkevidde — uanset hvad prompten siger, og uanset om §9.2's udelukkelsesliste er korrekt. Udelukkelseslisten styrer, hvad vi *sender*; den siger intet om, hvad modellen selv kan *hente*. En kildetekst, der indeholder en instruktion, er en ekstra vej til samme sted.

**Forslag:** runneren `-C`'er en per-kald midlertidig mappe **uden for repoet**, som kun indeholder netop den records input, og rydder den efter kaldet. Kanarietesten bliver en regressionstest. Rækkevidden af sandboxens læseadgang er ikke kortlagt (én måling mod hjemmemappen blev afvist af sessionens egne værn) — Task 2 kortlægger den, før mappens plads fastlægges.

---

## Global Constraints

- **Ingen prod-mutation.** Dagsværket rører hverken produktionsdatabasen eller kanoniske tabeller. Al databaseadgang er læse-kun mod en restore.
- **Ingen rigtige records gennem modellen.** 4.3a's eneste modelkald er på en syntetisk, ikke-identificerende record. De 10 afdøde records er 4.3b og kræver sin egen GO med hash-bundet udelukkelsesliste.
- **Fail-closed overalt.** Enhver fejl efterlader batchen `pending`. Der findes ingen delvis merge og ingen »grøn med forbehold«.
- **Ingen kildetekst i logs, fejl eller fixtures.** Fejl logges med type, aldrig med tekst — det gælder også `stderr` fra Codex. Og en fejl fanget under 4.3b må **ikke** gemmes som fixture med sit rigtige indhold: fixtures bygges syntetisk og mærkes som sådan.
- **Ingen opfundne priser.** Planen fastlægger `pricing`-strukturen; tallene leveres ved profil-GO fra en citeret kilde.
- **Modelpolitikken ændres ikke.** `gpt-5.6-terra` er arbejdshesten; `gpt-5.6-sol` kræver `escalation_reason` og kun på validator-flaggede records.

## Roadmappens seks adgangskrav

1. **Roadmapmål:** trin 4, den fælles fortolkningskæde og klausulgranularitet (#147/#148).
2. **Værdikædeled:** »Extractor-runner og modelkald« flyttes fra `specificeret` mod `isoleret implementeret`. Dagsværket gør ikke i sig selv leddet `integreret ende-til-ende` — det kræver 4.3b's rigtige kørsel og 4.4's ingest.
3. **Generel, profil eller legacy:** generel motor (runner, cache, fejltaksonomi, claim-kontrakt) plus 2018-20-profiludvidelse (`pricing`, ny `prompt_version`). Ingen legacy-afvikling; den gamle trin ③-vej røres ikke.
4. **Redaktionel værdi:** ingen direkte. 4.3a er infrastrukturen, der gør 4.3b's første rigtige claims mulige — og som afgør, om forbruget kan budgetteres, før trin 6 startes.
5. **Bevis:** én syntetisk record gennem `gpt-5.6-terra` med reelt forbrug i manifestet (§6.5), plus kanarietesten fra afvigelse C. Ingen neutralitetsmåling er relevant: intet skrives.
6. **Erstatter (muliggør):** intet erstattes i 4.3a. `ALLOWED_PREDICATES` blev allerede afløst i 4.2.

## Filoversigt

| Fil | Ændring |
| --- | --- |
| `.claude/skills/daa-extract/scripts/evidence_runner.py` | **Ny.** Runner med injicerbar `run_codex`-søm, cache, fejltaksonomi, regnskab. |
| `.claude/skills/daa-extract/scripts/test_evidence_runner.py` | **Ny.** Pytest mod fixtures; starter aldrig Codex. |
| `.claude/skills/daa-extract/references/evidence-claims-1.0.json` | **Ny.** Record-scoped claim-kontrakt (JSON Schema til `--output-schema`). |
| `.claude/skills/daa-extract/references/evidence-extract-prompt-1.0.0.md` | **Ny.** Prompt til den record-scoped kontrakt (afvigelse B). |
| `.claude/skills/daa-extract/scripts/evidence_extract.py` | `validate_record_claims`; `BatchManifest` + `prompt_sha256`/`exclusion_sha256`/`pricing_version`/`usage`; `load_profile` kræver promptfil + `pricing`. |
| `.claude/skills/daa-extract/references/extraction-profiles.json` | 2018-20 → **v1.3.0**: `pricing`, ny `prompt_version`. 1939 urørt. |
| `.claude/skills/daa-extract/scripts/export_model_exclusions.R` | **Ny.** Læse-kun eksport af udelukkelseslisten fra restoren (§9.2). |
| `.claude/skills/daa-extract/scripts/tests/fixtures/codex-exec/` | Udvides med fejltaksonomi-fixtures (mærket syntetiske). |
| `.github/workflows/ci.yml` | `test_evidence_runner.py` tilføjes til pytest-linjen (l. 103). |
| `.claude/skills/daa-extract/references/extract-prompt.md` | **Urørt.** |

---

### Task 1: Claim-kontrakten og dens validator (test fejler først)

§6.1 er eksplicit om, at `validate_output`'s strict bundle-vej **ikke** passer: den kræver hele renditionens tekst og rendition-absolutte offsets, mens runneren arbejder på et record-scoped artefakt, hvor modellen citerer klausul-**ordinaler**. Den nye kontrakt erstatter kun bundle-/offset-halvdelen — værdivalidering genbruges uændret.

- [ ] **Step 1.** Skriv `test_evidence_runner.py::test_validate_record_claims_*` først, rød. Dæk: claim uden ordinal; ordinal der ikke findes i eksporten; ordinal hvis `verbatim_sha256` ikke matcher; ukendt prædikat; `interpretation_kind` der modsiger tabellen; værdi der bryder prædikatets `value_kind`; `confidence` uden for [0,1]; persona-reglen.
- [ ] **Step 2.** `references/evidence-claims-1.0.json` — JSON Schema, der kan sendes til `--output-schema`. Lukket nøglesæt (`additionalProperties: false`) hele vejen ned; ingen fritekstfelter ud over `value.raw`.
- [ ] **Step 3.** `validate_record_claims(claims, export)` i `evidence_extract.py`. **Genbrug** `predicate_kind()` og `validate_claim_value()` fra 4.2 samt de seks `$defs` i `interpretation-schema.json` 1.1 — der skal ikke opstå et parallelt vokabular.
- [ ] **Step 4.** Persona-reglen efter §6.1's fund 3a: et `principal`-claim må citere klausuler under den helpost, personaen har mention i — **ikke** den snævrere »delmængde af personaens egne mention-observationer«, som `validate_output` bruger. Skriv forskellen som en kommentar med spec-henvisning, så den ikke senere »rettes« tilbage.

**Verify:** `python3 -m pytest .claude/skills/daa-extract/scripts/test_evidence_runner.py -q` grøn; alle negative prober røde før Step 3.

### Task 2: Arbejdsmappen som grænse (afvigelse C)

Denne task kommer **før** runneren, fordi dens resultat bestemmer runnerens form.

- [ ] **Step 1.** Kortlæg sandboxens læserækkevidde: kanariefiler i (a) søskendemappe til `-C`, (b) repoets rod, (c) en mappe uden for både repo og `/tmp`. Én kørsel pr. sted, syntetisk indhold, aldrig mod `work/` eller ægte PII. Skriv resultatet i planens revision før Step 2.
- [ ] **Step 2.** `evidence_runner.prepare_call_dir(record_input)` opretter en midlertidig mappe uden for repoet med præcis to filer: recordens input og outputskemaet. Ingen symlinks, ingen forældrereference.
- [ ] **Step 3.** Mappen ryddes i `finally` — også ved kvotestop og timeout. En efterladt mappe er et fund, ikke et restprodukt.
- [ ] **Step 4.** Regressionstest: kanariefilen uden for kaldets mappe må ikke kunne gengives. Testen bruger fixturen `sandbox-canary-read-outside-cwd.jsonl` som det **negative** eksempel (sådan så det ud, da grænsen manglede).

**Verify:** kanarietesten rød mod den gamle opsætning, grøn mod den nye. Rydningen bevist ved at fremtvinge en exception midt i kaldet.

### Task 3: Runneren, cachen og fejltaksonomien

- [ ] **Step 1.** `run_codex(argv) -> (jsonl_events, last_message)` som **injicerbar søm**. Testene leverer fixtures; produktionsstien bygger argv med alle flag fra §6.2 **plus** `--ignore-user-config` (afvigelse A) og stdin lukket.
- [ ] **Step 2.** Usage-parser: læs `turn.completed.usage` — fem felter (`input_tokens`, `cached_input_tokens`, `cache_write_input_tokens`, `output_tokens`, `reasoning_output_tokens`). Manglende `usage` på en ellers vellykket tur er `unknown`, ikke nul. Test mod `turn-completed-with-usage.jsonl`.
- [ ] **Step 3.** Per-record uforanderlig svar-cache (§6.3). Nøgle: `(profil, profilversion, model, prompt_sha256, record_input_sha256)`. Værdi: rå JSON-svar + usage. Cachen er append-only; en eksisterende nøgle med afvigende værdi er `CACHE_CONFLICT`, ikke en overskrivning.
- [ ] **Step 4.** Fejltaksonomi, alle fail-closed: `quota_exhausted`, `model_refusal`, `schema_violation`, `timeout`, `validation_failed`, `unknown`. Hver logges med type og record-nøgle, **aldrig** med tekst. Batchen forbliver `pending`.
- [ ] **Step 5.** Fixtures for de fem uobserverede fejltyper. **Mærk dem syntetiske i README'en** — kun `turn.completed` er observeret. Spec §6.5 kalder proben 2026-09-06's `turn.failed` »fixturen«, men den rå JSON findes ikke i repoet og blev ikke fundet ved eftersøgning; `quota_exhausted`-fixturen er derfor *rekonstrueret ud fra den dokumenterede form*, ikke observeret. Skriv det i README'en frem for at lade en senere læser tro andet.

**Verify:** pytest grøn uden at Codex nogensinde startes (bevis: testene kører med `run_codex`, der kaster ved kald).

### Task 4: Regnskab, manifest og profilbump

- [ ] **Step 1.** `BatchManifest` udvides med `prompt_sha256`, `exclusion_sha256`, `pricing_version`, `usage`. **Afgør eksplicit**, om `token_count` bliver et afledt felt af `usage` eller bevares — `complete_batch` og `reusable` (`evidence_extract.py:~296`) læser det i dag, og begge skal forblive grønne.
- [ ] **Step 2.** `pricing` i profilen: pr. model-id, med egen version. Model uden pris **stopper** kørslen (§6.4). Planen fastlægger strukturen; **tallene indsættes ved profil-GO fra en citeret kilde** og opfindes ikke her.
- [ ] **Step 3.** Skriv i manifestets dokumentation, at `cost_usd` er et *referencetal*: kørslen betales over abonnement (§6.7), så beløbet er en sammenlignelighedsstørrelse, ikke en faktura.
- [ ] **Step 4.** Batchstørrelse og budget. De to spec-krav ser ud til at trække hver sin vej, men gør det ikke: §6.1 er ubetinget (modellen ser **én record ad gangen**, og claims citerer ordinaler fra netop den records klausuler), §6.3's cache-nøgle er **pr. record**, og §6.4's »batches 5-10 records« er granulariteten for *manifest og regnskab* — ikke et fælles kald. Batchen er en regnskabs- og kvoteenhed.

  **Konsekvensen skal skrives eksplicit ind, fordi den er ubehagelig:** ét kald pr. record betyder, at probens ~21.554 input-tokens i fast overhead betales **pr. record**. De ~12,7 M input-tokens for 591 records er derfor den *faktiske* projektion, ikke et skrækeksempel, som batchning kan fjerne. Batchning amortiserer intet her.

  Den eneste tilgængelige amortisering er udbyderens egen prompt-cache — proben så 11.008 af 21.554 tokens cachet ved andet kald. Den effekt **skal måles i 4.3b** pr. batch og må ikke antages: den afhænger af, hvor tæt kaldene ligger i tid, og den er uden for vores kontrol.
- [ ] **Step 5.** Profil 2018-20 → **v1.3.0** (`pricing` + ny `prompt_version`). 1939-profilen urørt. `requires_human_go_for_change` gælder: bumpet kræver projektejerens GO.

**Verify:** `test_reimport_profile.py` og `test_evidence_extract.py` grønne; en profil uden `pricing` for den valgte model afvises med navngivet token.

### Task 5: Udelukkelseslisten (§9.2)

- [ ] **Step 1.** `export_model_exclusions.R` — læse-kun, `REPEATABLE READ READ ONLY`, altid `ROLLBACK`, samme form som `export_clause_source_texts.R`. Output: record-nøgler + hvilken regel der ramte, **ingen tekst og ingen navne**.
- [ ] **Step 2.** Implementér alle fire regler fra §9.2 (levende/uafklaret hovedperson; levende partner eller barn i samme `family`; partner uden dødsdato med vielse ≥1950 *eller uden vielsesdato*; tekstfilter »f.« + fødselsår ≥1950).
- [ ] **Step 3.** **Genmål mod restoren.** §9.2's tal (46+4, 13, 62, 2) er målt 2026-09-06. Sammenlign med egen måling og **rapportér afvigelsen** frem for at kopiere tallene. En afvigelse er ikke nødvendigvis en fejl — men den skal ses.
- [ ] **Step 4.** Runneren nægter at køre uden listen: manglende eller ikke-matchende `exclusion_sha256` er `EXTRACTION_EXCLUSION_REQUIRED`. Negativ test.
- [ ] **Step 5.** Udelukkede records bliver stående i køen med en synlig disposition. De er ikke tab, og de må ikke forsvinde ud af regnskabet.

**Verify:** eksporten kørt mod restoren; tal sammenholdt med §9.2; runneren afvist uden liste.

### Task 6: Rigtig kørsel + CI + rapport

- [ ] **Step 1.** `test_evidence_runner.py` tilføjes til `ci.yml:103`'s eksplicitte pytest-liste. **Uden det kører testen ingen steder** — 4.2's R8-lære.
- [ ] **Step 2.** Den rigtige kørsel (§6.5): **én syntetisk, ikke-identificerende record** gennem `gpt-5.6-terra`, med reelt forbrug i manifestet. Beviser forbrugsrapportering, cache-hit ved gentagelse, output-skema og mindst én fejltype ende-til-ende.
- [ ] **Step 3.** Kanarietesten køres som del af den rigtige kørsel — grænsen skal bevises på den opsætning, der faktisk sendes videre til 4.3b.
- [ ] **Step 4.** Rapport i `docs/evidensbaseret-genimport/` med alle hashes (prompt, kontrakt, profil, udelukkelsesliste, manifest) og de målte forbrugstal. Changelog-post. Opdatér `status.md`'s modenhedstabel for »Extractor-runner og modelkald«.
- [ ] **Step 5.** Ryd op: midlertidige mapper, lokale baser oprettet af dagsværket, og enhver cache-fil med indhold fra restoren.

**Verify:** CI grøn på alle seks jobs; rapportens tal genfindes i manifestet.

---

## Selvreview-checkliste

- [ ] Er de tre spec-afvigelser afgjort af projektejeren **før** Task 1 — ikke antaget undervejs?
- [ ] Kan nogen test starte Codex ved et uheld? (Sømmen skal kaste i testmiljø.)
- [ ] Er der ét eneste sted, hvor kildetekst kan havne i en log, en fejlbesked eller en cache-nøgle?
- [ ] Er `quota_exhausted`-fixturen mærket rekonstrueret frem for observeret?
- [ ] Er priserne stadig tomme pladser, eller er der sneget et gæt ind?
- [ ] Kører runneren stadig, hvis udelukkelseslisten mangler? (Den skal nægte.)
- [ ] Er kanarietesten grøn, fordi grænsen virker — eller fordi modellen tilfældigt ikke forsøgte?
- [ ] Er `extract-prompt.md` stadig urørt, og virker den gamle trin ③-vej?
- [ ] Er batchstørrelsen begrundet i overheadmålingen frem for i spec'ens skøn?
- [ ] Er §9.2's tal genmålt frem for kopieret?

## Anden læser

Planen skal læses af Codex `gpt-5.6-sol` før kodning, jf. decisions 2026-09-06 (valg 3). Læseren bedes særligt efterprøve:

1. **De tre spec-afvigelser.** De er alle til planforfatterens fordel (mere kontrol, nyere fil, ekstra flag) — netop derfor skal de efterprøves af en, der ikke har skrevet dem. Jf. `bekvemme-argumenter-i-egne-rulings`.
2. **Om afvigelse C er tilstrækkelig.** En per-kald mappe uden for repoet er en grænse, hvis sandboxen respekterer den. Kanariemålingen i Task 2 Step 1 skal afgøre det — planen må ikke hvile på, at den *formentlig* gør.
3. **Om `validate_record_claims` genbruger nok.** Et parallelt vokabular eller en anden datoform ville drive fra 4.2's tabel og først vise sig i 4.4.
4. **Om budgettallet i Task 4 Step 4 er ærligt.** Ét kald pr. record gør probens overhead til den faktiske regning (~12,7 M input-tokens for 591 records). Er der en amortisering, planen har overset — eller taler den tallet ned?
