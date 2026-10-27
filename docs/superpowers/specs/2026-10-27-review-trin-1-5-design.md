# Helhedsreview af dataarbejdet, trin 1-5 — grundlag (charter)

> Status: udkast til projektejerens godkendelse, 2026-10-27. Gren `docs/review-trin-1-5`.
> Forløber: projektejerens ønsker 19/10, 21/10 og 27/10 (hukommelsen `review-trin-1-5-med-fable`).

## 1. Hensigt

Projektejeren vil have et ærligt, uafhængigt svar på, om det store dataarbejde siden juni har **høj kvalitet** og
**dækker det behov, metoden skal dække** for Danmarks Adels Aarbog. Rapporten er kun til projektejeren, ikke til
foreningen. Den må gerne være direkte og ubehagelig. Reviewet ligger efter 5c-1 (i prod 2026-10-27) og før 5c-2 og
trin 6, så eventuelle grundlagsfejl kan rettes, før der bygges videre.

## 2. Spørgsmål, reviewet skal besvare

1. **Kvalitet.** Hvor solid er koden: SQL (skema, migrationer, verify, RLS, RPC'er), Python/R-pipelinen og testene?
   Det gælder duplikering, v1/v2/v3-filer side om side, konkurrerende definitioner, død eller forældet kode,
   navngivning, kompleksitet og testenes reelle dækning.
2. **Overengineering.** Hvor er der brugt uforholdsmæssigt mange kræfter på nicheproblemer? Det var en kendt tendens
   hos tidligere modeller.
3. **Blinde pletter.** Hvad burde metoden have løst, som slet ikke er taget op?
4. **Visionen.** Holder `vision.md` og `roadmap.md` som mål for årbogen? Reviewet må gerne udfordre selve visionen.
5. **Projektejerens beslutninger.** Er der selvmodsigende beslutninger? Er der kursskift, der aldrig blev gjort
   færdige? Er retningen glidet, uden at det blev besluttet? Er der valg, der set i bagklogskabens lys kostede meget?
   Hvert fund skal angive, hvad det kostede, og hvad der bør gøres anderledes fremover. Projektejeren mistede flere
   gange orienteringen i udviklingsretningen, så dette spor har særlig vægt.
6. **Bevisernes dækning.** Tester bevisrapporternes og verify-filernes kontroller faktisk det, de påstår?
7. **Udestående.** Samlet liste over det, der mangler før et godt, færdigt produkt: ikke udviklet, udskudt,
   parkeret eller kun syntetisk bevist.

## 3. Afgrænsning

**Med:** datamodellen og invarianterne (`datamodel-oversigt.md`, CLAUDE.md), ekstraktion, segmentering og validering
(`.claude/skills/daa-*/scripts/`), R-loadlaget, databasen (`schema.sql`, `db-migrations.sql`, `db-verify.sql`,
`db-rls.sql`, `tests/sql/`), genimport-kæden trin 1-5 inkl. specs, planer, bevisrapporter, runbooks og
prod-overførsler, og **de RPC'er (`red_*` m.fl.), som apps kalder**. De er datalag.

**Uden for:** `web/`, `mobile/`, `packages/` (egen senere runde). Trin 6 og den tredje årbog vurderes kun som
fremtidige krav: er grundlaget klar til dem?

## 4. Persondata (gælder hvert brief)

Hvert agent- og Codex-brief starter med en læseforbudsliste, fordi en reviewer ellers kan læse alt på disken
(Codex' sandbox er ikke en læsegrænse):

- `work/`, `work_1939_stamtavle/`, `work_presens/`, `~/.private/`, `*.dump`, `manifest*.json`, `kontrolark*`,
  `token*`, `aktoer*`, `.env*`, `~/.Renviron`.
- Ingen forespørgsler mod prod eller lokale baser. Reviewet arbejder kun på repoets filer.
- Postnøgler (`I-94`, record_key) og tal er i orden i output. Navne på levende personer må ikke citeres.

Committede filer (`docs/`, `decisions.md`, bevisrapporter, kode) er screenet og må læses direkte.
`.superpowers/sdd/*/progress.md` er ikke sporet. Den må læses af fase 0's beslutningsudtræk, men kun Ruling-linjer
og fund må gengives.

**Teknisk afskærmning (mit valg):** En tekstlig forbudsliste er ikke nok. Alle reviewere i fase 0-2 arbejder i en
**ren eksport af repoet** (`git archive HEAD` udpakket i scratchpad). Den indeholder kun sporede filer, så de
gitignorerede `work*`-mapper findes slet ikke. Codex startes med denne mappe som arbejdsmappe og `--sandbox
read-only`. Det eneste ikke-sporede input, ledgernes `progress.md`, gives kun til 0b som en udtrukket fil med
Ruling-linjer, som hovedsessionen selv har dannet med grep. Forbudslisten står stadig i hvert brief, som et ekstra
lag mod absolutte stier som `~/.private`.

**Hvad der committes (mit valg):** Agenterne skriver til hver sin mappe i scratchpad. Hovedsessionen læser hver
leverance og screener den for personnavne fra levende personer og citater fra ikke-sporede filer, før den kopierer den
til `docs/reviews/…` og committer. Rå output bliver aldrig committet.

## 5. Faser, modeller og kontrolpunkter

Rådet er at bruge den mindste model, der kan løse opgaven. Fable er dyrest og bruges én gang. Hvert `Agent`-kald
sætter `model` eksplicit. Workflow-værktøjet bruges ikke uden et særskilt ja.

### Fase 0 — oversigter (skrives før reviewerne starter)

| # | Leverance | Udføres af | Indhold |
|---|---|---|---|
| 0a | `maalinger.md` | hovedsessionen med scripts | (1) For hver funktion defineret i både `schema.sql` og `db-migrations.sql`: sammenlign den *sidste* definition i hver fil (det er den, der gælder), først rå og derefter normaliseret. Normaliseringen fjerner kun kommentarer og forskelle i whitespace og ignorerer forskellen mellem `CREATE` og `CREATE OR REPLACE`. Den røres ikke ved store/små bogstaver, skemapræfikser eller klausulrækkefølge. Rapportér begge tal, så en for aggressiv normalisering ikke kan skjule divergenser: antal i begge / identiske / divergerende og listen over divergerende. Migrationsfilen er idempotent og *skal* gentage definitioner, så det rå antal er ikke et fund. (2) Python/R/SQL-filer med versionssuffiks (`_v2`, `_v3` …) side om side, og om de ældre stadig importeres eller køres. (3) Filer, der hverken importeres, kaldes fra CI, skills eller runbooks (kandidater til død kode). (4) Test pr. trin: testfiler og CI-job pr. modul. (5) Størrelse pr. trin. |
| 0b | `beslutningskronologi.md` | Sonnet | Kilder: alle poster i `docs/decisions.md`, specs' afgørelsesafsnit (»Besluttet af projektejeren«, »Afgørelser«, »projektejerens afgørelse«), ledgernes `Ruling:`-linjer og bevisrapporternes »Fund«. Ordnet **pr. emne** (fx identitet, relationer/ægtefæller, placement/membership, narrativer/proveniens, id'er/overførsel, kontrolark/menneskelig godkendelse, prod-ceremonier, model/skema) og inden for emnet efter dato. Hver post: dato, kilde (fil:linje), beslutning, hvad den afløste eller ændrede, og hvem der besluttede (projektejer eller agent). Ledgerne findes kun for få perioder, så kronologien skal nævne, hvor den er ufuldstændig. Ingen vurdering, kun udtræk. |
| 0c | `systemkort.md` | Sonnet | Pr. trin (og forarbejdet fra sommeren: datamodel, første importer, 1939 C0-C3): mål ifølge roadmap, specs, planer, hovedfiler i kode og SQL, tests og CI-job, bevisrapporter, runbooks, prod-status (fra `status.md` og `database-current-state.md`) og åbne issues. |
| 0d | `udestaaende-raa.md` | Sonnet | Rå indsamling uden vurdering: `status.md`, åben backlog i `decisions.md`, ledgernes `minor (deferred)`, bevisrapporternes »kendte begrænsninger«, åbne GitHub-issues og de kendte punkter i hukommelsen (P-identiteten bag 1314, ordinal-rodfejlen, personoprettelse kun syntetisk bevist). |

0b, 0c og 0d skriver hver til sin egen mappe i scratchpad. Hovedsessionen samler og committer. **Kontrolpunkt 1:**
Projektejeren ser oversigterne, før fase 1 bruger tokens.

### Fase 1 — fagreviews

| # | Spor | Model | Input |
|---|---|---|---|
| 1a | Beslutningssporet (spørgsmål 5) | Opus | 0b + `vision.md`/`roadmap.md` + de citerede kilder ved behov |
| 1b | SQL-kvalitet (spørgsmål 1-2) | Opus | 0a + `schema.sql`/`db-migrations.sql`/`db-verify.sql`/`db-rls.sql`, med 0c som vejviser |
| 1c | Python/R-kvalitet og tests (spørgsmål 1-2) | Opus | 0a + `.claude/skills/daa-*/scripts/` + `tests/`, med 0c som vejviser |
| 1d | Adversarial kodereview | Codex (model-id verificeres i runtime før kaldet; projektejeren nævner 6.1 terra) | Samme filer som 1b og 1c, uden 1b/1c's fund, så blikket er uafhængigt |
| 1e | Bevisernes dækning (spørgsmål 6) | Codex | Bevisrapporterne, `db-verify.sql`, `tests/sql/`. Kendt eksempel på fejlklassen: 2a's tupel-digest dækker kun de 210 ældste promotion-rækker, fordi `supersedes_promotion_id` altid skrives siden 2b-i. Led efter mønsteret, ikke kun den ene forekomst. |

Efter hver Codex-runde afvejer Opus fundene: nødvendigt / forenklet / kendt begrænsning / afvist. **Kontrolpunkt 2:**
Projektejeren ser fase 1's fund, før Fable kaldes.

**Læselofter i fase 1 (mit valg):** Python/R alene er ca. 110.000 linjer og SQL ca. 56.000, så ingen reviewer læser
alt. 1b og 1c læser **højst 40 filer eller sektioner fuldt** hver. De udvælges efter systemkortet (0c), så hvert trin
og forarbejdet er repræsenteret med sine centrale moduler. Resten undersøges med grep og målingerne. Hver reviewer
lister i sin leverance, hvad der er læst fuldt, så dækningen er synlig. 1d (Codex) får samme loft og vælger selv
inden for det.

**Codex-model (mit valg):** Model-id'et for »6.1 terra« slås op i Codex-runtime, før 1d kaldes. Findes det ikke,
kører 1d ikke. Jeg spørger i stedet ved kontrolpunkt 1, om sol eller terra skal bruges. Jeg gætter ikke.

### Fase 2 — koncept og vision (spørgsmål 2-4 og 7, samlet)

Ét selvstændigt Fable-kald (`Agent`, `model: fable`, aldrig i en workflow). Input-bundtet er højst ca. 8.000
linjer: `vision.md`, `roadmap.md`, `teknisk-maalarkitektur.md`, `status.md`, invarianterne, 0b-0d og fase 1's
afvejede fund. Ingen rå kode. Bliver bundtet større, komprimerer hovedsessionen fase 1's fund til domme med henvisninger.
Loftet overskrides ikke. Fable må slå op i den rene eksport efter behov, men **højst 25 filer** (mit valg). Briefet
beder Fable liste sine opslag. Spørgsmålet: virker metoden for årbogen, hvad er overbygget, hvad mangler, og hvad i
visionen bør ændres?

### Fase 3 — samlet dom

Hovedsessionen (Opus) skriver rapporten: én dom pr. område på skalaen **solidt / solidt men overbygget / hul / bør
laves om**, med begrundelse og henvisninger. Derefter følger en prioriteret liste over handlinger, og listen over det
udestående. Projektejeren gennemgår rapporten. Trin 6 startes ikke før.

## 6. Leverancer og placering

`docs/reviews/2026-10-27-trin-1-5/`: `maalinger.md`, `beslutningskronologi.md`, `systemkort.md`,
`udestaaende-raa.md`, `fund-1a.md` … `fund-1e.md`, `fable-koncept.md`, `rapport.md`. Committes atomisk pr.
leverance på `docs/review-trin-1-5`. Rå agent-output bliver liggende i scratchpad.

## 7. Dosering

Omtrentligt antal kald: 3 × Sonnet (fase 0), 3 × Opus (1a-1c), 2 × Codex (1d-1e) + 2 Opus-afvejninger, 1 × Fable.
Hvert brief angiver sit læseloft (§5), så tokenforbruget kan ses på forhånd.

**Tyndt output (mit valg):** Et spor er tyndt, hvis det ikke besvarer sine spørgsmål med henvisninger til fil og
linje, eller hvis dets liste over læste filer viser, at et trin er sprunget over. Et tyndt spor gentages én gang med
samme model og et skarpere brief. Er det stadig tyndt, eskaleres et Sonnet-spor til Opus. Et Opus-spor eskaleres
**aldrig** til Fable uden projektejerens ja.

**Kontrolpunkterne (mit valg):** Der stoppes ved begge, og der kaldes ingen model i næste fase før projektejerens
svar. Hovedsessionen må skrive næste fases briefs i mellemtiden.

## 8. Mine valg (kan afvises)

- Dom-skalaen i fase 3 (projektejeren har ikke bekræftet den).
- Mappestrukturen i §6 og grennavnet.
- Fable placeres i fase 2 med oversigter og fund, ikke rå kode; sporene 1a-1c går til Opus frem for Fable.
- Kontrolpunkt 2 (fund før Fable), ud over projektejerens ønskede kontrolpunkt 1.
- Fase 0's emneinddeling for kronologien. Sonnet må tilføje emner.
- Ren `git archive`-eksport som teknisk afskærmning, og screening før commit (§4).
- Sammenligning af funktioner: sidste definition, rå og let normaliseret (§5, 0a).
- Læselofter: 40 filer for 1b-1d, 25 opslag for Fable, bundt ≤ ca. 8.000 linjer.
- Ingen gætning på Codex-model; ingen eskalering til Fable uden ja; stop ved kontrolpunkterne.
