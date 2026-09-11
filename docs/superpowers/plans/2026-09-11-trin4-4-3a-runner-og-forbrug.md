# Trin 4 · dagsværk 4.3a: model-runneren, svar-cachen og eligibility-ledgeren — implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `evidence_runner.py` kan kalde `gpt-5.6-terra` gennem `codex exec` for én record ad gangen, validere svaret mod en record-scoped claim-kontrakt, føre regnskab med reelt målt forbrug og stoppe fail-closed på hver fejltype — bag en **OS-håndhævet** læsegrænse, der gør §6.1's »én record ad gangen« til en faktisk grænse, og bag en eligibility-ledger, som runneren skal slå hver record op i, før den overhovedet bygger et kald.

**Architecture:** Et nyt motor-script `evidence_runner.py` med en injicerbar `run_codex`-søm (så tests aldrig starter Codex), en ny kontraktfil `references/evidence-claims-1.0.json` + `validate_record_claims` i `evidence_extract.py`, en ny promptfil `references/evidence-extract-prompt-1.0.0.md` skrevet til den record-scoped kontrakt, en per-record svar-cache, `BatchManifest` udvidet med fire felter, et R-eksportscript til eligibility-ledgeren, og en profilbump til 2018-20 v1.3.0 med `pricing`.

**Tech Stack:** Python 3 + pytest, `codex exec` (codex-cli 0.153.4), R (DBI/RPostgres) til læse-kun eksport, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-06-trin4-fortolkningskaede-og-klausulgranularitet-design.md` §6 (runner), §9.1-9.2 (privatliv, udelukkelse). Kravet »modellen ser én record ad gangen« står i **§6.1** og **§9.1** — spec'ens egne henvisninger til et »§19« er brudte (spec'en ender ved §12) og er ikke fulgt her, jf. R12.

**Forudgående måling:** `docs/evidensbaseret-genimport/runner-usage-probe-147-4-3a.md` (forbrugsproben, 2026-09-11). Planen bygger på dens tal, ikke på skøn.

---

---

## Revision 1 (2026-09-11) — efter adversarial gennemgang (Codex `gpt-5.6-sol`)

> Anden læser fandt **12 fund, heraf tre blokerende**. Revisionen går forud for den
> oprindelige plantekst, hvor de er uenige — og kroppen nedenfor er rettet, ikke kun
> overskrevet af dette forord (4.2's lære R2′).
>
> **Alle 12 fund blev accepteret.** Tre er efterprøvet selvstændigt før accept: §19's
> eksistens, budgetregnestykket og §9.1's rettighedskrav.

### R1 (BLOKERENDE, retter afvigelse C): per-kald-mappen er ingen læsegrænse

Planens egen afhjælpning var selvmodsigende: den konstaterede, at `-C` ikke begrænser
læsning — og foreslog derefter `-C` til en anden mappe som sikkerhedsgrænse. En proces, der
kan læse en søskendemappe, kan også bruge absolutte stier, `../../…`, hjemmemappen og
mount points. At mappen ligger »uden for repoet« ændrer ikke procesrettighederne.

Kanarietesten er heller ikke en adgangstest: at modellen ikke *valgte* at læse en fil er
ikke bevis for, at den ikke *kunne*. Planens egen selvreview-linje erkendte det og løste det
ikke.

**Rettet til:** 4.3b kræver en **OS-håndhævet** læsegrænse — isoleret container/VM eller en
sandbox-policy med allowlist-mount af kun prompt, record og skema; intet repo, ingen rigtig
hjemmemappe, ingen PII-mapper, ingen arvede hemmeligheder. Grænsen verificeres
**deterministisk**: en kommando, der forsøger kendte absolutte og relative stier og *skal*
få `EACCES`/»not found«. Kan CLI-sandboxen ikke levere det, stopper 4.3 med et navngivet
blocker-fund frem for at fortsætte. **Modeladfærd må ikke være sikkerhedsoraklet.**

### R2 (BLOKERENDE, retter Task 5): listen kræves, men bruges ikke

Planen krævede, at udelukkelseslisten *findes* og har den forventede hash. Den sagde intet
om, at runneren skal slå `record_key` op i den og **afvise kaldet**. En korrekt hashet liste
kunne altså være til stede, mens en levende persons record blev kørt. Spec §9.1 er ellers
utvetydig: »Modelkald kun for records, der består alle regler i 9.2.«

**Rettet til:** obligatorisk preflight, før prompt eller subproces overhovedet konstrueres —
(1) validér listeskema og hash, (2) slå den aktuelle `record_key` op, (3) ved fund: returnér
`excluded`, opret **intet** call-dir og start aldrig Codex, (4) test alle fire regelårsager
plus en record med flere årsager, (5) bevis det med en `run_codex`-søm, der eksploderer,
hvis den kaldes for en udelukket record.

### R3 (BLOKERENDE, retter Task 5): fravær på listen er ikke tilladelse

`exclusion_sha256` hashede kun eksportresultatet. Den bandt hverken reglernes version,
eksportscriptets hash, restore-/source-snapshottet, det komplette record-univers eller den
record-scoped eksports hash. En gammel eller fejlimplementeret — men internt korrekt hashet
— liste ville derfor blive accepteret. Det er særlig farligt, netop fordi *fravær* på en
udelukkelsesliste læses som tilladelse.

**Rettet til:** en hash-bundet **eligibility-ledger over hele batchuniverset**: én række pr.
record med eksplicit `eligible`/`excluded`, årsager, policyversion, regelscript-SHA,
source-/restore-identitet og record-input-SHA. Runneren må kun kalde modellen ved en
eksplicit `eligible`-række med matchende inputhash. En ukendt record afvises — den er ikke
tilladt, blot fordi den ikke står på en liste.

### R4 (MAJOR): Task 2 manglede et stopkriterium

Resultatet skulle »skrives i planens revision«, hvorefter arbejdet fortsatte. Task 2 Step 1
er nu en **gate**: dokumenteret read-denial er adgangskrav til resten af dagsværket; ellers
NO-GO og redesign af isolationen. Ingen subproceskode skrives før gaten er bestået.

### R5 (MAJOR): budgettallet passede ikke til planens egen konfiguration

Planen brugte 21.554 tokens/kald — målingen **med** brugerkonfiguration — samtidig med at
afvigelse A gør `--ignore-user-config` obligatorisk. Med planens egen konfiguration er tallet
15.266. Efterregnet: **9.022.206 ≈ 9,02 M** input-tokens for 591 records, ikke 12,7 M.
Forskellen er 3,7 M tokens.

Fejlen var forfatterens egen og blev *forstærket* i en tidligere rettelse, som ophøjede 12,7
M til »den faktiske projektion«. Rettet til scenarier frem for ét tal, og baseline
genmåles med den endelige argv og isolationsmekanisme.

### R6 (MAJOR): eskaleringsgaten er halv

§6.4 kræver både `escalation_reason` **og** at kun validator-flaggede records må bruge
`gpt-5.6-sol`. Koden håndhæver i dag kun årsagen (`evidence_extract.py:147`), og ingen task
dækkede flagbeviset. Tilføjet til Task 4 med negative tests: Sol uden flag, med flag fra
forkert inputhash, og blandet batch.

### R7 (MAJOR): cache-identiteten var underspecificeret

Cache-nøglen manglede claim-skemaets SHA og runner-/CLI-kontraktversion — et ændret
outputskema kunne ellers genbruge et gammelt råsvar. Og §6.3's krav om at udvide `reusable`
var kun nævnt som »eksisterende tests skal forblive grønne«. Den fulde genbrugskontrakt med
negative tests pr. felt er nu Task 3's ansvar.

### R8 (MAJOR): private artefakters rettigheder var overset

Spec §9.1 kræver `0600`, ignoreret mappe, aldrig commit. Planen sagde kun »midlertidig
mappe« og senere oprydning. `tempfile`-standarder og brugerens `umask` er ikke en kontrakt.
Krav tilføjet: mappe `0700`, filer `0600`, atomisk oprettelse uden symlinks, og
rettighedstests.

### R9 (MAJOR): promptfilens mapping var uklar for 1939

Afvigelse B's fire påstande holder alle — det bekræftede anden læser. Men **løsningen** var
ufuldstændig: begge profiler har i dag samme `prompt_version` (`evidence-extract-1.0.0`), og
planen ville gøre filbinding global i `load_profile` uden at sige, hvilken fil 1939 så
resolver til. Rettet: hver profil får et eksplicit `prompt_file` + `prompt_sha256`, valideret
mod en tilladt references-mappe uden path traversal, med tests for begge profiler og en
regressionstest af legacy-trin ③.

### R10 (MAJOR): prisstrukturen kunne ikke implementeres som beskrevet

»Pr. model-id, med egen version« siger ikke, hvordan de fem usage-felter prissættes: tælles
reasoning som output? Hvordan behandles `cached_input_tokens` og `cache_write_input_tokens`?
Valuta, enhed, kildedato, afrunding? Skema og cost-formel skal ligge fast **før** profil-GO,
med håndregnede tests.

### R11 (MINOR): »alle tre fundet ved at måle« var upræcist

Afvigelse B blev fundet ved **kodeeftersyn**, ikke måling. Og at hele forskellen på 6.288
tokens består af netop AGENTS.md, `config.toml` og tre skills, er en *slutning* fra en
tokendifference — indholdet blev ikke observeret. Hvert grundlag mærkes nu `målt`,
`observeret`, `kodeeftersyn`, `rekonstrueret` eller `antaget`.

### R13 (2026-09-11): isolationsgaten er efterprøvet og BESTÅET

R1 krævede en OS-håndhævet læsegrænse, ellers NO-GO for 4.3. Den er nu målt, ikke antaget.

**Mekanismen:** macOS Seatbelt (`sandbox-exec`) om `codex exec`. Profil-skabelon og
adgangstest ligger i `.claude/skills/daa-extract/scripts/sandbox/`.

**Tre målinger:**

1. **Deterministisk adgangstest, ingen model:** `work/`, `work_1939_stamtavle/`,
   `work_presens/` og `~/.private/` nægtes alle (`rc=1`); `docs/` og call-dir forbliver
   tilgængelige. Testen er selv efterprøvet mod en profil **uden** spærringer, hvor den
   korrekt melder `GATE_FAILED` — et værn, der aldrig er set fejle, er ikke et værn.
2. **Modellen forsøgte og blev nægtet:** bedt om at hente en fil i en *syntetisk* spærret
   mappe (og opfordret til at prøve flere metoder) svarede den `KAN IKKE LÆSE` efter eget
   udsagn at have prøvet »en alternativ læsemetode«. Kanariestrengen optrådte ikke i
   hændelsesstrømmen. Fixture: `sandbox-gate-denies-model.jsonl`.
3. **Codex kører normalt inde i grænsen:** `usage` rapporteres (15.256 input-tokens).

**Vejen dertil er værd at kende.** Codex' egen `--sandbox-state-readable-root` ser ud til at
være præcis mekanismen, men kræver et udokumenteret internt JSON-skema (`permissionProfile`),
som ikke kunne gættes — og en runner, der afhang af det, ville knække ved næste CLI-version.
En ren allowlist-profil blev forsøgt først og fik Codex til at fejle med `EPERM`: CLI'en har
brug for flere stier i hjemmemappen end forudset. Og `codex exec --sandbox read-only` inde i
en ydre Seatbelt fejler ligeledes; nestet Seatbelt går ikke.

**To ærlige forbehold, som Task 2 skal lukke:**

- Profilen er **deny-baseret**, ikke den allowlist anden læser anbefalede. Den nægter de
  *kendte* PII-mapper; en **ny** mappe med persondata ville ikke automatisk være dækket. At
  finde det minimale sæt stier, Codex faktisk behøver, er ingeniørarbejde — ikke et
  principspørgsmål — men det er ikke gjort.
- Codex' egen `~/.codex/auth.json` er stadig læsbar for modellen. Det er ingen forværring
  (den er det også i dag, helt uden grænse), men det er ikke lukket.

### R12 (MINOR): §19 findes ikke

Planen henviste gennemgående til »spec §19«. **Efterprøvet: spec'en ender ved §12.** »§19«
optræder kun som brudte interne krydshenvisninger i spec'en selv (linje 353 og 581), som
denne plan kopierede ukritisk. Kravet »modellen ser én record ad gangen« står reelt i **§6.1**
og **§9.1**. Alle henvisninger er rettet; spec'ens egen brudte reference registreres som et
selvstændigt punkt til en senere spec-revision.

---

## Spec-afvigelser — GODKENDT af projektejeren 2026-09-11

> **Status:** A og B godkendt ubetinget. **C godkendt betinget** (»hvis det er muligt«) — og
> muligheden er efterprøvet samme dag: **isolationsgaten er BESTÅET**, se R13 nedenfor.
> Beslutningen er registreret i `docs/decisions.md`, så den ikke kun lever i chatten.



Tre steder afviger denne plan fra den godkendte spec. De er planens vigtigste indhold og skal afgøres før Task 1. Grundlaget er forskelligt og mærkes derfor eksplicit: **A** hviler på en *måling* (tokendifference) plus en *slutning* om, hvad differencen består af; **B** på *kodeeftersyn*; **C** på en *observation* (kanariekørslen) — afhjælpningen i C er indtil Task 2's gate en *hypotese*, ikke et bevis.

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

### C. »Én record ad gangen« skal håndhæves af operativsystemet, ikke af prompten

Dette er den alvorligste af de tre. §6.1's og §9.1's »modellen ser én record ad gangen« er i dag en instruktion i prompten. Kanarietesten i proben viser, at det ikke er en grænse: en fil lagt uden for kaldets `-C`-mappe blev læst, fordi modellen **eksekverede en shell-kommando** (`/bin/zsh -lc "… sed -n '1,20p' ../canary/uden-for-cwd.txt"`) og gengav indholdet ordret.

`--sandbox read-only` forbyder skrivning og netværk, ikke kommandokørsel. `-C` sætter arbejdsmappen, ikke en læsegrænse. `codex exec` har ingen flag til at slå værktøjsbrugen fra (efterprøvet i `--help`).

Kører runneren et sted, hvorfra `work/`, `work_1939_stamtavle/`, restore-eksporten eller `~/.private/` kan nås, er prosa om levende personer inden for rækkevidde — uanset hvad prompten siger, og uanset om §9.2's udelukkelsesliste er korrekt. Udelukkelseslisten styrer, hvad vi *sender*; den siger intet om, hvad modellen selv kan *hente*. En kildetekst, der indeholder en instruktion, er en ekstra vej til samme sted.

**Forslag (revideret efter R1).** En per-kald mappe er *ikke* svaret: en proces, der kan læse en søskendemappe, kan også bruge absolutte stier, `../../…`, hjemmemappen og mount points, så `-C` til et andet sted giver orden og oprydning — ikke isolation. Kravet er en **OS-håndhævet allowlist-læsegrænse** (isoleret container/VM eller en sandbox-policy, der kun monterer prompt, record og skema), verificeret **deterministisk** med en kommando, der forsøger kendte stier og *skal* få `EACCES`/»not found«. Kan `codex exec` ikke levere det på denne maskine, stopper 4.3 med et navngivet blocker-fund frem for at fortsætte på en formodning. Kanarietesten beholdes, men som *supplement*: den viser adfærd, ikke adgang — at modellen ikke forsøgte, er ikke bevis for, at den ikke kunne.

---

## Global Constraints

- **Ingen prod-mutation.** Dagsværket rører hverken produktionsdatabasen eller kanoniske tabeller. Al databaseadgang er læse-kun mod en restore.
- **Ingen rigtige records gennem modellen.** 4.3a's eneste modelkald er på en syntetisk, ikke-identificerende record. De 10 afdøde records er 4.3b og kræver sin egen GO med hash-bundet eligibility-ledger — og at Task 2's isolationsgate er bestået.
- **Fail-closed overalt.** Enhver fejl efterlader batchen `pending`. Der findes ingen delvis merge og ingen »grøn med forbehold«.
- **Ingen kildetekst i logs, fejl eller fixtures.** Fejl logges med type, aldrig med tekst — det gælder også `stderr` fra Codex. Og en fejl fanget under 4.3b må **ikke** gemmes som fixture med sit rigtige indhold: fixtures bygges syntetisk og mærkes som sådan.
- **Ingen opfundne priser.** Planen fastlægger `pricing`-skema og cost-formel; tallene leveres ved profil-GO fra en citeret kilde med dato.
- **Private artefakter efter §9.1.** Call-dir `0700`, alle filer `0600`, atomisk oprettelse uden symlinks, privat placering uden for repoet, eksplicit ignore-regel for varige lokale artefakter. `tempfile`-standarder og brugerens `umask` er ikke kontrakten — rettighederne testes.
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
| `.claude/skills/daa-extract/scripts/export_model_eligibility.R` | **Ny.** Læse-kun eksport af eligibility-ledgeren — hele batchuniverset, `eligible`/`excluded` pr. record (§9.1-9.2). |
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

### Task 2: Isolationsgaten (afvigelse C, revideret af R1 og R4)

Denne task kommer **før** runneren, fordi dens resultat bestemmer runnerens form — og fordi den kan standse dagsværket. Task 1 må gerne ligge før: claim-validatoren er uafhængig af processen. **Ingen subproceskode skrives, før gaten er bestået.**

- [x] **Step 1 — GATE, fail-closed. BESTÅET 2026-09-11 (se R13).** Mekanismen er macOS Seatbelt om `codex exec`; profil-skabelon og adgangstest ligger i `.claude/skills/daa-extract/scripts/sandbox/`. Gaten er bevist både positivt (spærrede stier nægtes, nødvendige forbliver tilgængelige) og negativt (testen melder `GATE_FAILED` mod en profil uden spærringer). Modellen forsøgte aktivt og blev nægtet.
- [ ] **Step 1b — stram profilen mod en allowlist.** Den beståede profil er **deny-baseret**: den nægter de *kendte* PII-mapper, så en ny mappe med persondata ikke automatisk er dækket. Find det minimale sæt stier, Codex faktisk behøver (et første allowlist-forsøg gav `EPERM`), og vend profilen om. Overvej samtidig, om `~/.codex/auth.json` kan lukkes for modellen. **Indtil da gælder deny-listen, og adgangstesten skal udvides, hver gang en ny PII-mappe opstår** — det er svagheden ved formen og skal stå i rapporten.
- [ ] **Step 2.** `evidence_runner.prepare_call_dir(record_input)` opretter call-dir'et med præcis to filer: recordens input og outputskemaet. Mappe `0700`, filer `0600`, atomisk oprettelse, ingen symlinks, ingen forældrereference (§9.1).
- [ ] **Step 3.** Mappen ryddes i `finally` — også ved kvotestop, timeout og exception. En efterladt mappe er et fund, ikke et restprodukt. Det samme gælder rå svar-cache og fejloutput.
- [ ] **Step 4.** To adskilte tests, der ikke må forveksles: (a) **adgangstesten** fra Step 1 — deterministisk, uden model; (b) **kanarietesten** — en model bedt om at hente en fil uden for grænsen, som supplement. Fixturen `sandbox-canary-read-outside-cwd.jsonl` er det **negative** eksempel: sådan så det ud, da grænsen manglede. En grøn kanarietest alene beviser intet, fordi modellen kan have ladet være med at forsøge.

**Verify:** adgangstesten viser `EACCES`/»not found« for hver af de syv stier; kanarietesten rød mod den gamle opsætning, grøn mod den nye; rydning bevist ved at fremtvinge en exception midt i kaldet; rettigheder efterprøvet med `stat`.

### Task 3: Runneren, cachen og fejltaksonomien

- [ ] **Step 1.** `run_codex(argv) -> (jsonl_events, last_message)` som **injicerbar søm**. Testene leverer fixtures; produktionsstien bygger argv med alle flag fra §6.2 **plus** `--ignore-user-config` (afvigelse A) og stdin lukket.
- [ ] **Step 2.** Usage-parser: læs `turn.completed.usage` — fem felter (`input_tokens`, `cached_input_tokens`, `cache_write_input_tokens`, `output_tokens`, `reasoning_output_tokens`). Manglende `usage` på en ellers vellykket tur er `unknown`, ikke nul. Test mod `turn-completed-with-usage.jsonl`.
- [ ] **Step 3.** Per-record uforanderlig svar-cache (§6.3). Nøgle: `(profil, profilversion, model, prompt_sha256, record_input_sha256)` **plus claim-skemaets SHA og runner-/CLI-kontraktversion** (R7) — uden de to sidste kan et ændret outputskema genbruge et gammelt råsvar. Værdi: rå JSON-svar + usage. Cachen er append-only; en eksisterende nøgle med afvigende værdi er `CACHE_CONFLICT`, ikke en overskrivning. Cachefiler `0600` i privat mappe (§9.1).
- [ ] **Step 3b.** `green` samles fra cachen (§6.3): en batch er kun `green`, når **hver** record i den har en valideret cachepost. Delvis dækning er `pending`. Og udvid `reusable` (`evidence_extract.py:~296`) eksplicit: ændret `prompt_sha256`, `exclusion_sha256`, `pricing_version` eller claim-kontrakt **skal** give ikke-genbrug. Én negativ test pr. felt — det er ikke nok, at de eksisterende tests forbliver grønne.
- [ ] **Step 4.** Fejltaksonomi, alle fail-closed: `quota_exhausted`, `model_refusal`, `schema_violation`, `timeout`, `validation_failed`, `unknown`. Hver logges med type og record-nøgle, **aldrig** med tekst. Batchen forbliver `pending`.
- [ ] **Step 5.** Fixtures for de fem uobserverede fejltyper. **Mærk dem syntetiske i README'en** — kun `turn.completed` er observeret. Spec §6.5 kalder proben 2026-09-06's `turn.failed` »fixturen«, men den rå JSON findes ikke i repoet og blev ikke fundet ved eftersøgning; `quota_exhausted`-fixturen er derfor *rekonstrueret ud fra den dokumenterede form*, ikke observeret. Skriv det i README'en frem for at lade en senere læser tro andet.

**Verify:** pytest grøn uden at Codex nogensinde startes (bevis: testene kører med `run_codex`, der kaster ved kald).

### Task 4: Regnskab, manifest og profilbump

- [ ] **Step 1.** `BatchManifest` udvides med `prompt_sha256`, `exclusion_sha256`, `pricing_version`, `usage`. **Afgør eksplicit**, om `token_count` bliver et afledt felt af `usage` eller bevares — `complete_batch` og `reusable` (`evidence_extract.py:~296`) læser det i dag, og begge skal forblive grønne.
- [ ] **Step 2.** `pricing` i profilen: pr. model-id, med egen version. Model uden pris **stopper** kørslen (§6.4). **Skema og cost-formel skal ligge fast før profil-GO** (R10) og besvare: tælles `reasoning_output_tokens` som output? Hvordan prissættes `cached_input_tokens` og `cache_write_input_tokens`? Enhed (pr. million tokens), valuta, kilde-URL og kildedato, samt decimalbaseret afrunding. Håndregnede tests pr. felt. **Tallene indsættes ved profil-GO fra en citeret kilde** og opfindes ikke her.
- [ ] **Step 3.** Skriv i manifestets dokumentation, at `cost_usd` er et *referencetal*: kørslen betales over abonnement (§6.7), så beløbet er en sammenlignelighedsstørrelse, ikke en faktura.
- [ ] **Step 4.** Batchstørrelse og budget. De to spec-krav ser ud til at trække hver sin vej, men gør det ikke: §6.1 er ubetinget (modellen ser **én record ad gangen**, og claims citerer ordinaler fra netop den records klausuler), §6.3's cache-nøgle er **pr. record**, og §6.4's »batches 5-10 records« er granulariteten for *manifest og regnskab* — ikke et fælles kald. Batchen er en regnskabs- og kvoteenhed.

  Konsekvensen er, at probens faste overhead betales **pr. record**; batchning amortiserer intet. **Budgettet opgives som scenarier, ikke som ét tal** (R5 — den oprindelige plan brugte 21.554, målingen *med* brugerkonfiguration, selv om afvigelse A gør `--ignore-user-config` obligatorisk):

  | Scenarie | Overhead/kald | 591 records, før recordindhold | Status |
  | --- | --- | --- | --- |
  | Planens konfiguration (`--ignore-user-config`), uden cache | 15.266 | **≈ 9,02 M** | den relevante projektion |
  | Samme, med den observerede cacheandel | — | lavere, **ikke garanteret** | skal måles i 4.3b |
  | Legacy-konfiguration (med brugerkonfig) | 21.554 | ≈ 12,7 M | kun til sammenligning |

  Payload, output og reasoning opgøres særskilt. Udbyderens prompt-cache (proben så 11.008 af 21.554 cachet ved andet kald) er uden for vores kontrol og afhænger af, hvor tæt kaldene ligger i tid — den **måles** i 4.3b, antages ikke. Baseline genmåles med den endelige argv og den isolationsmekanisme, Task 2 ender med.
- [ ] **Step 5.** Profil 2018-20 → **v1.3.0** (`pricing` + `prompt_file`/`prompt_sha256`). `requires_human_go_for_change` gælder: bumpet kræver projektejerens GO.
- [ ] **Step 6 (R9).** Promptens mapping gøres entydig: **hver** profil får et eksplicit `prompt_file` + `prompt_sha256`, valideret mod en tilladt references-mappe uden path traversal. I dag har begge profiler samme `prompt_version`, så en global filbinding i `load_profile` ville efterlade uafklaret, hvad 1939 resolver til. 1939 peger fortsat på sin nuværende adfærd. Tests for **begge** profiler plus en regressionstest af legacy-trin ③.
- [ ] **Step 7 (R6).** Eskaleringsgaten gøres hel. §6.4 kræver både `escalation_reason` **og** at kun validator-flaggede records må bruge `gpt-5.6-sol`; koden håndhæver i dag kun årsagen (`evidence_extract.py:147`). Tilføj et hash-bundet validator-resultat pr. record til manifest/preflight, og afvis Sol, med mindre **alle** valgte records har et tilladt flag og en årsag. Negative tests: Sol uden flag; flag fra forkert inputhash; blandet batch.

**Verify:** `test_reimport_profile.py` og `test_evidence_extract.py` grønne; en profil uden `pricing` for den valgte model afvises med navngivet token.

### Task 5: Eligibility-ledgeren (§9.1-9.2, omskrevet af R2 og R3)

Den oprindelige task krævede kun, at en udelukkelsesliste *fandtes* og havde rigtig hash. To huller: runneren slog aldrig op i den, og hashen bandt kun eksportresultatet. Begge er lukket her. Grundreglen er, at **fravær ikke er tilladelse**.

- [ ] **Step 1.** `export_model_eligibility.R` — læse-kun, `REPEATABLE READ READ ONLY`, altid `ROLLBACK`, samme form som `export_clause_source_texts.R`. Output er **hele batchuniverset**: én række pr. record med eksplicit `eligible`/`excluded`, årsager, policyversion, regelscript-SHA, source-/restore-identitet og record-input-SHA. **Ingen tekst og ingen navne.**
- [ ] **Step 2.** Implementér alle fire regler fra §9.2 (levende/uafklaret hovedperson; levende partner eller barn i samme `family`; partner uden dødsdato med vielse ≥1950 *eller uden vielsesdato*; tekstfilter »f.« + fødselsår ≥1950). En record kan rammes af flere regler — alle årsager bæres med.
- [ ] **Step 3.** **Genmål mod restoren.** §9.2's tal (46+4, 13, 62, 2) er målt 2026-09-06. Sammenlign med egen måling og **rapportér afvigelsen** frem for at kopiere tallene. En afvigelse er ikke nødvendigvis en fejl — men den skal ses.
- [ ] **Step 4 — preflight, før prompt eller subproces overhovedet bygges.** Rækkefølgen er en del af kravet: (1) validér ledgerens skema og hash; (2) slå den aktuelle `record_key` op; (3) er rækken `excluded` — eller findes den slet ikke — returnér `excluded`/`unknown_record`, opret **intet** call-dir og start **aldrig** Codex; (4) er rækken `eligible`, kræv at dens `record_input_sha256` matcher det input, kaldet faktisk vil sende. Manglende eller ikke-matchende ledger er `EXTRACTION_ELIGIBILITY_REQUIRED`.
- [ ] **Step 5.** Tests: alle fire regelårsager hver for sig; en record med flere årsager; en ukendt record; en `eligible`-række med afvigende inputhash. **Beviset** er en `run_codex`-søm, der kaster, hvis den overhovedet kaldes for en ikke-eligible record — det er ikke nok at tjekke en returværdi.
- [ ] **Step 6.** Udelukkede records bliver stående i køen med en synlig disposition. De er ikke tab, og de må ikke forsvinde ud af regnskabet.

**Verify:** eksporten kørt mod restoren; tal sammenholdt med §9.2; sømmen beviser, at Codex aldrig startes for en ikke-eligible record.

### Task 6: Rigtig kørsel + CI + rapport

- [ ] **Step 1.** `test_evidence_runner.py` tilføjes til `ci.yml:103`'s eksplicitte pytest-liste. **Uden det kører testen ingen steder** — 4.2's R8-lære.
- [ ] **Step 2.** Den rigtige kørsel (§6.5): **én syntetisk, ikke-identificerende record** gennem `gpt-5.6-terra`, med reelt forbrug i manifestet. Beviser forbrugsrapportering, cache-hit ved gentagelse, output-skema og mindst én fejltype ende-til-ende.
- [ ] **Step 3.** Både adgangstesten og kanarietesten køres som del af den rigtige kørsel — grænsen skal bevises på præcis den opsætning, der sendes videre til 4.3b, ikke på en tidligere.
- [ ] **Step 4.** Rapport i `docs/evidensbaseret-genimport/` med alle hashes (prompt, kontrakt, profil, eligibility-ledger, manifest), de målte forbrugstal og **isolationsgatens denial-resultater**. Changelog-post. Opdatér `status.md`'s modenhedstabel for »Extractor-runner og modelkald«.
- [ ] **Step 5.** Ryd op: midlertidige mapper, lokale baser oprettet af dagsværket, og enhver cache-fil med indhold fra restoren.

**Verify:** CI grøn på alle seks jobs; rapportens tal genfindes i manifestet.

---

## Selvreview-checkliste

- [ ] Er de tre spec-afvigelser afgjort af projektejeren **før** Task 1 — ikke antaget undervejs?
- [ ] **Bestod isolationsgaten (Task 2 Step 1) med deterministisk `EACCES` på alle syv stier** — eller er der skrevet subproceskode oven på en formodning?
- [ ] Er kanarietesten grøn, fordi grænsen virker — eller fordi modellen tilfældigt ikke forsøgte? (Den er supplement, aldrig bevis.)
- [ ] **Kan runneren nå at bygge et kald for en record, der ikke har en `eligible`-række?** Beviser sømmen det, eller tjekkes kun en returværdi?
- [ ] Behandles en **ukendt** record som tilladt noget sted? (Fravær er ikke tilladelse.)
- [ ] Binder ledgerens hash også regler, script, snapshot og record-input — eller kun eksportresultatet?
- [ ] Kan nogen test starte Codex ved et uheld? (Sømmen skal kaste i testmiljø.)
- [ ] Er der ét eneste sted, hvor kildetekst kan havne i en log, en fejlbesked, en fixture eller en cache-nøgle?
- [ ] Er call-dir `0700` og filerne `0600` — efterprøvet med `stat`, ikke antaget af `tempfile`?
- [ ] Er `quota_exhausted`-fixturen mærket rekonstrueret frem for observeret?
- [ ] Er priserne stadig tomme pladser, eller er der sneget et gæt ind? Er cost-formlen entydig for alle fem usage-felter?
- [ ] Kan `gpt-5.6-sol` vælges for en record uden validator-flag?
- [ ] Giver ændret `prompt_sha256`, `exclusion_sha256`, `pricing_version` eller claim-kontrakt **ikke**-genbrug — med en test pr. felt?
- [ ] Er `extract-prompt.md` stadig urørt, virker den gamle trin ③-vej, og er det entydigt, hvilken promptfil **1939** resolver til?
- [ ] Er budgettet opgivet som scenarier med planens egen konfiguration (15.266), ikke som ét tal fra legacy-konfigurationen (21.554)?
- [ ] Er §9.2's tal genmålt frem for kopieret?
- [ ] Er hvert grundlag mærket `målt` / `observeret` / `kodeeftersyn` / `rekonstrueret` / `antaget`?

## Anden læser — UDFØRT 2026-09-11

Codex `gpt-5.6-sol` har læst planen jf. decisions 2026-09-06 (valg 3) og fandt **12 fund, heraf tre blokerende**. Alle er accepteret og indarbejdet i Revision 1 ovenfor; tre blev efterprøvet selvstændigt før accept (§19's eksistens, budgetregnestykket, §9.1's rettighedskrav). Dommen over de tre afvigelser: **A berettiget**, **B berettiget** (alle fire påstande holder i koden), **C berettiget men utilstrækkelig** — hvilket er R1.

Reviewet blev kørt i en isoleret mappe uden for repoet med kun de nødvendige filer, netop efter det princip afvigelse C handler om.

Oprindelig brief til læseren (bevaret):

1. **De tre spec-afvigelser.** De er alle til planforfatterens fordel (mere kontrol, nyere fil, ekstra flag) — netop derfor skal de efterprøves af en, der ikke har skrevet dem. Jf. `bekvemme-argumenter-i-egne-rulings`.
2. **Om afvigelse C er tilstrækkelig.** En per-kald mappe uden for repoet er en grænse, hvis sandboxen respekterer den. Kanariemålingen i Task 2 Step 1 skal afgøre det — planen må ikke hvile på, at den *formentlig* gør.
3. **Om `validate_record_claims` genbruger nok.** Et parallelt vokabular eller en anden datoform ville drive fra 4.2's tabel og først vise sig i 4.4.
4. **Om budgettallet i Task 4 Step 4 er ærligt.** Ét kald pr. record gør probens overhead til den faktiske regning (~12,7 M input-tokens for 591 records). Er der en amortisering, planen har overset — eller taler den tallet ned?
