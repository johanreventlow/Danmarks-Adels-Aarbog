---
name: daa-extract
description: >-
  Parser Dansk Adels Aarbog (DAA) stamtavle-PDF til den evidensbaserede
  Supabase-datamodel. Brug denne skill ALTID når brugeren vil udtrække,
  parse, importere eller indlæse data fra en trykt adelsårbog / DAA-udgave /
  stamtavle-PDF — også når de blot siger "parse årbogen", "udtræk personerne
  fra PDF'en", "byg databasen fra bogen", "load stamtavlen" eller nævner
  pdftotext på adelsårbogen. Pipeline: deterministisk tekstudtræk +
  segmentering, LLM-struktureret fakta-udtræk per post (default Sonnet,
  Opus-fallback), blokerende validering, og R-load til Supabase. Bevarer
  altid prosaen som narrativ; udtrækker rygrad selektivt.
---

# DAA-udtræk: stamtavle-PDF → evidensbaseret datamodel

## Formål og filosofi

Dansk Adels Aarbog er den **autoritative kilde**. Hver post i stamtavlen er
tæt prosa med daterede gerninger. Vi gør to ting på én gang:

1. **Bevarer prosaen 100 % ordret** som `narrative` (substrat, fuldtekstsøgbar).
2. **Udtrækker rygraden selektivt** som `assertion` + `conclusion` + `citation`.

Det betyder: et *overset* fakta er kun under-strukturering (kan forfremmes
senere fra narrativen) — aldrig datatab. Den farlige fejl er *forkert* udtræk.
Hele designet optimerer derfor for at fange forkerte udtræk (validering), ikke
for at presse alt ud af prosaen.

**Læs `docs/daa-extraction-archetype.md` (i repo-roden) før udtræk** — det er
kontrakten for hvad der udtrækkes, hvad der bevidst IKKE udtrækkes (tredjeparts-
fælderne), og dato-kvalifikatorerne. Datamodellen selv: `schema.sql` i repo-roden.
Skemaet for trin ③'s output: `references/extraction-schema.json` (i denne skill).

## Pipeline (5 trin)

Trin 1-2 og 4 er **deterministisk kode** (ingen model, ingen fejlrisiko).
Trin 3 er det eneste LLM-trin. Trin 5 loader.

```
PDF ──①pdftotext──> rå tekst ──②segment.py──> posts.json
   ──③LLM-udtræk──> extracted.json ──④validate.py──> {clean.json, review.json, escalation.json}
   ──④b Opus-eskalering (flaggede) ──> opdateret clean.json + escalation-diff.md
   ──⑤load_daa.R──> Supabase   (kun clean.json; review.json kræver menneske)
```

### ① Tekstudtræk (deterministisk)

```bash
scripts/extract_text.sh "<pdf>" <første-side> <sidste-side> > work/raw.txt
```

PoC-scope: stamtavle s. 93-247. Scriptet bruger `pdftotext -layout` og
fjerner sidehoved/footer-støj (`.indd`-linjer, løbende sidehoved, sidetal).

### ② Segmentering (deterministisk)

```bash
python3 scripts/segment.py work/raw.txt > work/posts.json
```

Producerer én record per stamtavle-post med: `linje` (romertal-sektion),
`slaegtled`, `aegteskab_kontekst` (hvilken union børnene hører til), `nr`, og
`raw_text` (postens fulde ordrette prosa). Håndterer side-brud-fortsættelse.

**Segmenteringen er edition-følsom.** Hvis posttal eller headers ser forkerte
ud, justér regexerne i `segment.py` — det er forventet ved en ny udgave.
Verificér altid: antal poster ≈ forventet, og at `nr` er sammenhængende per linje.

### ③ Struktureret fakta-udtræk (LLM — det eneste model-trin)

For **hver** post i `posts.json`, udtræk **kun struktureret rygrad** til JSON
efter skemaet i `references/extraction-schema.json`. Kør ét nummer ad gangen
(lille kontekst = mindre drift). Default-model **Sonnet**; dispatch i batches
som subagents.

**Narrativen udledes IKKE af LLM'en.** Kerneløftet er at prosaen bevares 100%
ordret — at lade en model reproducere lang verbatim-tekst inviterer trunkering/
parafrase. `segment.py` har allerede den ordrette `raw_text` per (linje,nr), og
`validate.py` fletter den deterministisk ind i de rene records. LLM'en
udtrækker altså kun fakta/relationer/slægtskab.

**`boern` udledes DETERMINISTISK, ikke af LLM'en.** Børne-referencen er regulær
tekst ("3 børn: Tiende slægtled, II, nr. 31-35" / "Søn: … nr. 199."). LLM-trinnet
missede den systematisk, så `validate.py` (trin ④) parser den fra kilde-prosaen
og overskriver et evt. LLM-`boern`. LLM'en *må* stadig udfylde feltet, men det
ignoreres. OBS: `boern.linje` er bogens INTERNE gren-tæller i slægtleddet, IKKE
JSON-linjen (matcher kun ~85%) — se `docs/decisions.md` om kryds-gren-tvetydighed.

Brug den **frosne prompt** i `references/extract-prompt.md` uændret — den er den
autoritative kontrakt for trin ③ (postens input-felter, dato-/kilde_span-krav, hvad
der er rygrad, embeder-vs-karriere, model-tier). Rediger promptfilen (ikke ad hoc pr.
kørsel), og bump `prompt-version` i dens header ved ændringer, så modeller/kørsler kan
sammenlignes uden prompt-drift. NB: `date_min`/`date_max` udledes nu deterministisk i
trin ④ fra `date_raw` — LLM'en skal prioritere at få `date_raw` ordret rigtigt.

Gem ét JSON-objekt per post til `work/extracted/<linje>-<nr>.json`.

**Model-tier:** Sonnet er default. Hvis trin ④ flagger en post, gen-kør KUN
den post med Opus (`--model opus`). Opus er fallback, ikke standard — de tætte
middelalderposter med tredjeparts-personer er hvor svagere modeller fejler.

### ④ Validering (deterministisk, BLOKERENDE)

```bash
python3 scripts/validate.py work/posts.json work/extracted/ \
  --clean work/clean.json --review work/review.json
```

Tjekker de 6 regler (se `docs/daa-extraction-archetype.md` §5). En post med ÉT brud
ryger i `review.json` og **loades ikke**. Scriptet udskriver en review-rapport
med præcis hvilken regel der brød og hvor. Et menneske skal gennemgå
`review.json`, rette (eller gen-køre med Opus), og flytte godkendte poster til
`clean.json` før load.

Dette er bevidst blokerende: vi hellere mangler en post end loader en forkert.

### ④b Auto-eskalering (agent-orkestreret, ÉT forsøg)

Hvis trin ④ flagger poster i `escalation.json`, køres denne drift af agenten:

1. **Snapshot Sonnet-output FØR overskrivning:** kopiér hver `work/extracted/<linje>-<nr>.json`
   til `work/extracted/<linje>-<nr>.sonnet.json` (gemmer Sonnet's version til sammenligning).

2. **Dispatch en Opus-subagent** (samme rolle som trin ③, samme skema) med postens
   `grunde` fra worklisten ("tidligere forsøg missede/brød: …") som kontekst.
   Opus overskriver `work/extracted/<linje>-<nr>.json` med sit re-udtræk.

3. **Merge plumbingen (deterministisk):**
   ```bash
   python3 scripts/escalate_merge.py work/posts.json work/extracted/ work/extracted/ \
     work/escalation.json work/clean.json work/review.json --diff work/escalation-diff.md
   ```
   
   Scriptet re-validerer hvert Opus-output: består det **uden blokerende brud** OG
   **har det ikke flere R8-misses end Sonnet-snapshotten**, promoveres det til
   `clean.json` (markeret `_escalated: true`); ellers sikres det i `review.json`.
   Diff-rappen (`escalation-diff.md`) viser hvad der ændrede sig per post.

4. **Overflad resultatet:** "N poster eskaleret til Opus, M reddet/promoveret,
   K stadig i review — se `work/escalation-diff.md`." Stadig-fejlende poster kræver
   menneske.

**ÉT forsøg per post:** gen-eskalér aldrig en post der allerede er prøvet med Opus.

### ⑤ Load til Supabase (R)

```bash
Rscript scripts/load_daa.R work/clean.json "DAA 2018-20" \
  --import-key=daa:2018-20:reventlow
```

**Append som default** (ingen TRUNCATE, review 12 2026-07-02): en ny slægt
sameksisterer med allerede loadede slægter; id'er allokeres fra `MAX(id)`.
`--reset` tømmer model-tabellerne først (kun ved en fuld gen-load fra bunden —
cascade-sletter ALT afledt data, inkl. redaktionel historik).

Loader hver post som: `narrative` (fuld prosa, source = DAA-udgaven) +
`fact`/`assertion`/`conclusion`/`citation` for rygraden + `family`/
`family_member` for slægtskab + `relation` for godser/embeder/begivenheder.
Login fra `~/.Renviron` (samme som `supabase_load.R`). Korrektionsdygtige loads
skal altid angive en eksplicit, reload-stabil `--import-key=...`; nøglen må aldrig
udledes af visningstitlen. Ældre loads uden nøgle skal køres med `--legacy-import`;
de er fortsat synlige, men kan ikke rettes i OCR-kvalitetsarket. Regenererer til sidst
`person.visning_*`-cachen fra konklusionerne.

**Forældrefamilie-slot (Problem 2):** hver 'barn'-`family_member`-række ledsages af
`member_evidence()` — et `fact('forældrefamilie')` + `assertion(objekt=familien)` +
citation (udgaven) + afklaret conclusion — så slægtskabet er evidens-komplet og
konkurrerende forældre-påstande fra andre udgaver kan hænges på samme slot. **Kræver
at DB'en er migreret** (`db-migrations.sql`: `assertion.objekt_type/objekt_id`,
`family_member`-EXCLUDE-constraint) — loaderen fejler ellers på objekt-kolonnerne.

**Erstatter** det håndtransskriberede udsnit i `supabase_load.R` — det var kun
en opstart. `load_daa.R` er den fremadrettede loader.

## Hurtig kørsel (hele PoC-scope)

```bash
cd <repo>
mkdir -p work/extracted
.claude/skills/daa-extract/scripts/extract_text.sh \
  "Dansk Adels Aarbog - Reventlow - Særudgave.pdf" 93 247 > work/raw.txt
python3 .claude/skills/daa-extract/scripts/segment.py work/raw.txt > work/posts.json
# trin ③: udtræk per post (se ovenfor) -> work/extracted/*.json
python3 .claude/skills/daa-extract/scripts/validate.py \
  work/posts.json work/extracted/ --clean work/clean.json --review work/review.json
# gennemgå work/review.json (menneske) -> godkend -> derefter:
Rscript .claude/skills/daa-extract/scripts/load_daa.R work/clean.json "DAA 2018-20" \
  --import-key=daa:2018-20:reventlow
```

`work/` er en arbejdsmappe — git-ignorér den (kan indeholde levende-persondata).

## Privat 1939-undtagelseskø

### Kildebundet dual-rendition-evidens (1939-v2)

Kør fra worktree-roden. Start med at materialisere de fire private, kildebundne
artefakter. CLI'en læser hver inputfil som bytes én gang, har ingen outputsti i
rapporten og opretter alle outputs eksklusivt; brug derfor altid nye filnavne ved
en ny kørsel.

```bash
/usr/bin/python3 .claude/skills/daa-extract/scripts/prepare_dual_rendition_evidence_1939.py \
  --baseline ../../../work_1939_stamtavle/clean_1939_v2.json \
  --calamari ../../../work_1939_stamtavle/full_ocr_calamari_r6_clean.txt \
  --raw ../../../work_1939_stamtavle/raw.txt \
  --pdf "../../../Dansk Adels Aarbog - Reventlow 1939.pdf" \
  --profile-version 1939-v2 \
  --calamari-occurrences-out work/task19-1939-pilot/calamari-occurrences-v2.json \
  --raw-occurrences-out work/task19-1939-pilot/raw-occurrences-v2.json \
  --evidence-out work/task19-1939-pilot/dual-evidence-v2.json \
  --report-out work/task19-1939-pilot/dual-evidence-report-v2.json
```

Den eksisterende private `coverage-review.json` er en bevaret, uversioneret V1-
artefakt og må ikke omskrives. Opret derfor den friske, eksklusive V2-template,
før den første kø bygges:

```bash
/usr/bin/python3 .claude/skills/daa-extract/scripts/prepare_coverage_1939.py \
  --make-review-template \
  --baseline ../../../work_1939_stamtavle/clean_1939_v2.json \
  --out work/task19-1939-pilot/coverage-review-v2.json
```

Brug derefter den source-bundne evidence-fil som Task 6's `--evidence` og den
friske template som `--review`; kø og rapport er diagnostiske og eksklusive:

```bash
/usr/bin/python3 .claude/skills/daa-extract/scripts/prepare_review_queue_1939.py \
  --baseline ../../../work_1939_stamtavle/clean_1939_v2.json \
  --evidence work/task19-1939-pilot/dual-evidence-v2.json \
  --review work/task19-1939-pilot/coverage-review-v2.json \
  --calamari ../../../work_1939_stamtavle/full_ocr_calamari_r6_clean.txt \
  --raw ../../../work_1939_stamtavle/raw.txt \
  --pdf "../../../Dansk Adels Aarbog - Reventlow 1939.pdf" \
  --profile-version 1939-v2 \
  --queue-out work/task19-1939-pilot/review-queue-manifest-v2.json \
  --report-out work/task19-1939-pilot/review-queue-report-v2.json
```

Generér derefter V2-menneskearket fra den deterministiske kø:

```bash
/usr/bin/python3 .claude/skills/daa-extract/scripts/make_human_review_1939.py \
  --baseline ../../../work_1939_stamtavle/clean_1939_v2.json \
  --queue-manifest work/task19-1939-pilot/review-queue-manifest-v2.json \
  --source-manifest work/task19-1939-pilot/review-queue-manifest-v2.json \
  --review work/task19-1939-pilot/coverage-review-v2.json \
  --calamari ../../../work_1939_stamtavle/full_ocr_calamari_r6_clean.txt \
  --raw ../../../work_1939_stamtavle/raw.txt \
  --calamari-first-pdf-page 496 \
  --out work/task19-1939-pilot/menneskeark-undtagelsesko-v2.html

open work/task19-1939-pilot/menneskeark-undtagelsesko-v2.html
```

Den deterministiske audit-stikprøve ligger allerede i
`review-queue-manifest-v2.json` og `review-queue-report-v2.json`. I HTML'en:
søg efter baselineposten, kontrollér kandidaterne, vælg/fortryd, genindlæs siden
og brug **Eksportér privat kladde**. Browserens `localStorage`, HTML'en og den
eksporterede `1939-review-kladd.json` er kladder; JSON-eksporten er den varige,
private overdragelse og skal opbevares uden for Git.

Efterforankr browser-eksporten med adapteren. Brug altid næste ledige run-suffix:
alle fire outputfiler oprettes eksklusivt, og den omskrevne choices-fil er det
eneste korrekte input til den efterfølgende konvertering.

```bash
/usr/bin/python3 .claude/skills/daa-extract/scripts/anchor_review_choices_1939.py \
  --choices /sti/til/1939-review-kladd.json \
  --queue-manifest work/task19-1939-pilot/review-queue-manifest-v2-run-e.json \
  --baseline ../../../work_1939_stamtavle/clean_1939_v2.json \
  --calamari ../../../work_1939_stamtavle/full_ocr_calamari_r6_clean.txt \
  --raw ../../../work_1939_stamtavle/raw.txt \
  --calamari-occurrences work/task19-1939-pilot/calamari-occurrences-v2-run-f.json \
  --raw-occurrences work/task19-1939-pilot/raw-occurrences-v2-run-f.json \
  --base-evidence work/task19-1939-pilot/dual-evidence-v2-run-f.json \
  --calamari-first-pdf-page 496 \
  --wrapper-out work/task19-1939-pilot/human-anchored-candidates-v3-run-b.json \
  --evidence-out work/task19-1939-pilot/composed-evidence-v3-run-b.json \
  --report-out work/task19-1939-pilot/human-anchor-report-v3-run-b.json \
  --rewritten-choices-out work/task19-1939-pilot/1939-review-kladd-rewritten-v3-run-b.json

jq '{anchored_count, parked_count, parked}' \
  work/task19-1939-pilot/human-anchor-report-v3-run-b.json

/usr/bin/python3 .claude/skills/daa-extract/scripts/prepare_coverage_1939.py \
  --choices-to-decisions work/task19-1939-pilot/1939-review-kladd-rewritten-v3-run-b.json \
  --queue-manifest work/task19-1939-pilot/review-queue-manifest-v2-run-e.json \
  --anchored-candidates work/task19-1939-pilot/human-anchored-candidates-v3-run-b.json \
  --out work/task19-1939-pilot/coverage-decisions-v3-run-b.json

/usr/bin/python3 .claude/skills/daa-extract/scripts/prepare_review_queue_1939.py \
  --baseline ../../../work_1939_stamtavle/clean_1939_v2.json \
  --evidence work/task19-1939-pilot/composed-evidence-v3-run-b.json \
  --review work/task19-1939-pilot/coverage-decisions-v3-run-b.json \
  --calamari ../../../work_1939_stamtavle/full_ocr_calamari_r6_clean.txt \
  --raw ../../../work_1939_stamtavle/raw.txt \
  --pdf "../../../Dansk Adels Aarbog - Reventlow 1939.pdf" \
  --profile-version 1939-v2 \
  --queue-out work/task19-1939-pilot/publication-queue-v3-run-b.json \
  --report-out work/task19-1939-pilot/publication-report-v3-run-b.json
```

Læs altid hele parkeringsrapporten, og undersøg hver parkering; adapteren gætter
aldrig. `composed-evidence` er et komplet source-bundet bundle: base-evidensen
bevares for alle andre baseline-keys, og kun validerede human-entries erstatter
deres egen tomme slot. Task-5-filen med præcis `{decisions, audit_results}` bruges
som `prepare_review_queue_1939.py --review` sammen med composed evidence som
`--evidence`; queue- og report-output er publikationsjoinets filbaserede resultat.

Der findes ingen approval-capable privat coverage-materializer. Workflowet stopper
derfor ved review-/fil-GO. Ny coverage-materialisering kræver særskilt design,
godkendelse og replay; den må ikke udledes af publikationsrapportens `GO`.

`work/`-artefakterne og browserens eksport er private og ignorerede; de må aldrig
committes. Overskriv eller slet ikke tidligere resultater for at genkøre: vælg nye,
versionssuffikserede filnavne. Et `GO` fra et review-værktøj er kun review-go; det er
ikke coverage-materialiserings-, database-, loader- eller deployment-GO.

V2-piloten bruger `dual-evidence-v2.json` som source-bundet evidens og den komplette,
stadig uafgjorte `coverage-review-v2.json` som konservativ review-template: poster
uden en komplet kandidat og positiv proveniens bliver `human_required`. Samme-side-
forslag i HTML'en er kun visningshjælp og bliver aldrig automatisk accepteret. Et namespaced
`presentation:1939-v2:post:<indeks>`-id gør manglende eller kolliderende parser-id'er
stabile inden for de fastlåste kilder; id'et er ikke positiv proveniens. Task 5
ignorerer sådanne id'er ved ankerindlæsning og parkerer altid et valgt
`presentation:`-id som `menneskeark`, også hvis en kandidatfil forsøger at give det
en komplet, fabrikeret kildebro. Den fælles autoritative accepted-candidate-
validator afviser desuden et `presentation:`-id i enhver coverage- eller
slutbeslutningssti. Derfor bliver komplet classifier-evidens med et sådant id
`human_required`, Task 5 kan ikke ankre det, og legacy-templates, Task 4-eksporter
og Task 6's publikationsgate afviser det som positiv evidens.

Task 6 accepterer kun source-løs evidens som den komplette, eksakte
`unreviewed`-template med heltalsfeltet `schema_version: 1`, baseline-hash og uden kandidat-, proveniens-, konflikt-,
blokker-, audit- eller beslutningsfelter; den normaliseres til nul kandidater.
Evidens med kandidater kræver `schema_version: 1`, præcis de seks source-felter
med hashes fra de aktuelle CLI-input og eksakt baseline-dækning uden dubletter.
Ukendte root-, entry-, kandidat- og proveniensfelter afvises. Kandidatens
Calamari- og rå-OCR-intervaller valideres mod de samme bytes, som source-hashene
blev beregnet fra, og råuddragets SHA-256 skal matche det aktuelle tekstudsnit.
Alle offentlige Task 4-6 JSON-grænser kræver det eksakte JSON-heltal `1`; `true`,
`1.0`, `"1"` og manglende schema-version afvises.

### Legacy source-løs fallback (ikke del af V2-sekvensen)

Task 6 kan fortsat acceptere en komplet source-løs `unreviewed`-template som
konservativ fallback, men den sti er ikke en fortsættelse af ovenstående V2-flow
og må ikke skrive til de samme V2-filnavne. Brug kun fallbacken som en særskilt,
versionsmærket kørsel uden positive kandidater.

Uden den eksakte ankermapping parkeres et kandidatvalg som `menneskeark`; der må
aldrig konstrueres en positiv kobling fra HTML'ens samme-side-forslag. En senere
slutkonvertering kan kun bruge den særskilte anchored-candidates-wrapper: en minimal
`accepteret` beslutning tæller kun,
når `(baseline_record_key, candidate_id)` entydigt joiner samme ejer i en komplet,
source-bundet evidence-fil med matchende positiv proveniens og uden konflikt.
Alle automatiske og menneskeligt accepterede kandidat-id'er samt Calamari-/rå-
intervaller valideres samlet for global injektivitet. Berigede legacy-ankre er
ikke en alternativ sandhedskilde: de accepteres kun med deres eksakte
statusafhængige grammar, når locator, kandidat-id, kandidatindeks, spans,
tekstsnit, sider, brotype og råhash alle matcher den aktuelle baseline,
source-bundne evidence og de aktuelle OCR-kilder. Task 5-output er tilsvarende
minimalt og eksakt: `accepteret` har kun nøgle, status og kandidat-id;
`menneskeark` har kun nøgle, status og reason; `eksplicit_dublet` har kun nøgle,
status og dubletmål. `auto_resolved` må kun forekomme i den deterministiske
auditpartition, mens `human_required` og `source_blocked` aldrig må forekomme i
audit. Beslutnings- og auditnøgler skal være disjunkte, og begge artefakter
skrives først efter at den samlede partition er valideret.
Den offentlige rapportbygger er altid diagnostisk `NO-GO`, også når den får et
tidligere valideret review-state-objekt. `GO` kan kun sættes i CLI'ens interne
rapportgrænse efter en ny parsing, hashing, evidensvalidering, klassifikation og
review-derivering fra de oprindelige input-bytes; et videregivet state-objekt
giver aldrig publikationsautoritet.
Alle scripts bruger eksklusiv oprettelse og
nægter at overskrive eksisterende output. Slet eller genbrug derfor aldrig V1/V5
som genkørselsmål. Ingen genereret fil under `work/` må committes.

En source-løs reviewfil er kun gyldig som fuldt dækkende, strengt `unreviewed`
template med eksakt `schema_version: 1` og uden beslutnings- eller auditfelter.
Task 5's eksakte `{decisions, audit_results}`-output er den eneste source-løse
beslutningsform; accepterede kandidatvalg får deres kildeidentitet fra det
obligatoriske source-bundne evidence-join. Foreløbige Task 5-valg tæller aldrig
som afsluttede; kun joinede minimale slutbeslutninger tæller menneskeposter som
gennemgået, og kun et
schema-gyldigt `audit_confirmed` kan opfylde en audit. `audit_failed` og
`audit_undecidable` blokerer den berørte regelgruppe og dermed publikation.

## 1939 v50 import-preview (ikke-skrivende)

Brug denne vej efter en afsluttet v50-reconciliation, når personer, narrativer,
facts, relationer, provenance og forventede databaseændringer skal kontrolleres
før reimport. Brug **ikke** `load_daa.R --dry-run`: den gamle loader udfører
midlertidige writes og tager loader-låse, selv om transaktionen bagefter rulles
tilbage.

Byg først det DB-frie, hashbundne preview fra de eksakte godkendte v50-input:

```bash
/usr/bin/python3 .claude/skills/daa-extract/scripts/prepare_reimport_1939_v50.py \
  --reconciliation work/task20-1939-full/source-record-reconciliation-v50.json \
  --reconciliation-report work/task20-1939-full/source-record-reconciliation-report-v50.json \
  --ledger work/task20-1939-full/source-record-ledger-v3-ditlev.json \
  --materialization work/task20-1939-full/boundary-materialization-v3-ditlev.json \
  --clean /Users/johanreventlow/TypeScript/danmarksadelsaarbog/work_1939_stamtavle/clean_1939_v3.json \
  --calamari /Users/johanreventlow/TypeScript/danmarksadelsaarbog/work_1939_stamtavle/full_ocr_calamari_r6_clean.txt \
  --output work/task21-1939-v50-import-preview/import-preview-v1.json \
  --report work/task21-1939-v50-import-preview/import-preview-v1-report.md
```

Builderen er pinned til v50-, report-, ledger-, materialization-, clean- og
Calamari-hashene. Den bogfører hver source record præcis én gang, klassificerer
legacy `kilde_span` ordret mod v50-verbatim og sætter altid
`canonical_mutations_authorized: false`. Genuinely-new, structural og
cross-reference må aldrig skabe personer.

Kør derefter den aktuelle Supabase-sammenligning. Credentials læses fra
`~/.Renviron`; angiv dem aldrig på kommandolinjen eller i rapporten:

```bash
Rscript .claude/skills/daa-extract/scripts/preview_reimport_1939_v50.R \
  --input=work/task21-1939-v50-import-preview/import-preview-v1.json \
  --output=work/task21-1939-v50-import-preview/database-preview-v1.json \
  --report=work/task21-1939-v50-import-preview/database-preview-v1-report.md \
  --source-edition='DAA 1939'
```

Databasevejen afviser transaction pooler-port 6543, starter `BEGIN READ ONLY`,
verificerer `transaction_read_only=on`, whitelister SQL til read-only grammar og
rollbacker/lukker forbindelsen før lokale output skrives. Manglende offentlige
tabeller/kolonner stopper kørslen. Manglende `private.source_record` bevares som
en eksplicit capability-blocker i en delvis `NO-GO`-rapport; den må aldrig
fortolkes som en tom tabel eller som tilladelse til at antage inserts.

Alle preview-output oprettes eksklusivt under `work/` og må ikke committes.
`dry_run_gate` kan kun være GO for en komplet kontrolkørsel. `reimport_gate`
forbliver NO-GO, indtil identiteter, parkeret provenance, private source records
og en særskilt godkendt writer/replay/rollback-plan er på plads.

## Vigtige principper

- **Hver DAA-udgave er én `source`.** Modstridende udgaver = separate kilder,
  håndteret indfødt af påstand/konklusion. Sæt source-udgaven korrekt i load.
- **Påstande er uforanderlige.** Rettelser = ny påstand + ny konklusion, aldrig
  overskrivning.
- **Cache-felter** (`visning_*`, `koen`) skrives aldrig direkte — regenereres.
- **Tredjeparts-personer** nævnt i prosaen (konger, paver, vidner) oprettes
  IKKE som entiteter (archetype §3).
- Senere TNG-import er **enrichment** (anden, svagere kilde) — forurener ikke
  dette DAA-grundlag.
