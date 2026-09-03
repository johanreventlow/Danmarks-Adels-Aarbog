# Evidensbaseret genimport styringsgrundlag Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Indfør et autoritativt, LLM-synligt værdigrundlag, roadmap, teknisk målarkitektur og statussnapshot, som styrer alt kommende genimport- og årbogsarbejde uden at gøre roadmapet bindende for projektets øvrige spor.

**Architecture:** Fire fokuserede dokumenter adskiller stabil vision, prioriteret roadmap, teknisk målarkitektur og driftfølsom status. Rodinstruktioner, `/daa-extract`-skillen og dokumentationsindekset peger på dokumenterne i én fast læserækkefølge; beslutningslog og changelog registrerer myndighed og indførelse uden at kopiere indholdet.

**Tech Stack:** Markdown, repository-instruktioner (`CLAUDE.md`, `AGENTS.md`, `SKILL.md`), Git og shell-baseret link-/indholdskontrol.

**Spec:** `docs/superpowers/specs/2026-08-25-evidensbaseret-genimport-styringsgrundlag-design.md`

## Global Constraints

- Scope er kun import og genimport af trykte DAA-årbøger, herunder kildebevaring, fortolkning, identitetsafstemning, kanonisk promotion og publicering.
- Vision og målarkitektur må kun ændres efter en udtrykkelig projektbeslutning, som samtidig registreres i `docs/decisions.md`.
- Roadmappets rækkefølge må kun ændres gennem en begrundet beslutningspost; implementerende agenter må ikke omprioritere programmet.
- `status.md` må ikke opfinde live produktionsstatus; driftfølsomme påstande skal have verificeringsdato eller markeres som ikke genverificerede.
- Historiske specs, planer og reviews bevares som historik og omskrives ikke til aktuel status.
- Ingen produktionsdata, databaseobjekter, importkode, reviewkode eller publiceringskode ændres.
- Der tilføjes ingen CI-håndhævelse i denne omgang.
- De fire autoritative dokumenter kopieres ikke i fuld længde ind i instruktioner eller logs; indgangene linker til dem.
- Den eksisterende `mobile/AGENTS.md` ændres ikke.
- Hver task afsluttes med fokuseret dokumentverifikation, `git diff --check` og en separat commit.

---

## File Map

Create authoritative documents:

- `docs/evidensbaseret-genimport/vision.md` — stabilt, ikke-teknisk værdigrundlag og definition af succes.
- `docs/evidensbaseret-genimport/roadmap.md` — ét aktivt programmål, efterfølgende rækkefølge og adgangskrav til nye planer.
- `docs/evidensbaseret-genimport/teknisk-maalarkitektur.md` — stabil teknisk oversættelse af visionen, uden dagsstatus eller implementeringsopgaver.
- `docs/evidensbaseret-genimport/status.md` — dateret og commit-bundet snapshot af faktisk modenhed og næste tilladte arbejde.

Modify discovery and instruction surfaces:

- `CLAUDE.md` — obligatorisk, scope-afgrænset læserækkefølge for Claude.
- `AGENTS.md` — ny rodinstruktion med samme scope og læserækkefølge for Codex.
- `.claude/skills/daa-extract/SKILL.md` — kræv styringsgrundlaget læst før skillens operationelle workflow.
- `docs/README.md` — gør dokumentpakken til den primære indgang for genimportstatus og ret den forældede 1939-roadmaptekst.

Modify governance history:

- `docs/decisions.md` — registrér valgt dokumentmodel, myndighed og ændringsregler.
- `docs/changelog.md` — registrér, at styringsgrundlaget er indført; ingen funktionel eller produktionsmæssig ændring.

Historical evidence used as source, not modified:

- `docs/superpowers/specs/2026-08-02-evidensbaseret-genimport-og-multislaegt-design.md`
- `docs/superpowers/plans/2026-08-02-evidensbaseret-genimport-og-multislaegt.md`
- `docs/superpowers/reviews/2026-08-22-evidensbaseret-genimport-afvigelsesvurdering.md`
- `docs/decisions.md` section `BESLUTTET: evidensbaseret genimport — retning efter afvigelsesvurderingen`
- `docs/superpowers/plans/2026-08-22-1939-v50-c3-atomisk-apply.md`

---

### Task 1: Opret vision og styrende roadmap

**Files:**

- Create: `docs/evidensbaseret-genimport/vision.md`
- Create: `docs/evidensbaseret-genimport/roadmap.md`

**Interfaces:**

- Consumes: det godkendte design, August-designet, afvigelsesvurderingen og beslutningen om rækkefølgen C3 → narrativnøgle → generel writer → 2018-proveniens.
- Produces: de to øverste myndighedslag, som alle senere dokumenter og instruktioner linker til.

- [ ] **Step 1: Skriv de fejlende eksistens- og kontraktchecks**

Kør før filerne oprettes:

```bash
test -f docs/evidensbaseret-genimport/vision.md
test -f docs/evidensbaseret-genimport/roadmap.md
rg -n "^## Vision$|^## Bindende principper$|^## Ikke-mål$|^## Definition af succes$|^## Ændringsmyndighed$" docs/evidensbaseret-genimport/vision.md
rg -n "^## Aktivt programmål$|^## Styrende rækkefølge$|^## Adgangskrav til nye planer$|^## Modenhedstilstande$|^## Kontrollerede afbrydelser$|^## Ændringsmyndighed$" docs/evidensbaseret-genimport/roadmap.md
```

Expected: mindst første `test -f` fejler, fordi dokumentpakken endnu ikke findes.

- [ ] **Step 2: Opret `vision.md` med den godkendte ikke-tekniske vision**

Dokumentet skal have denne indledning og disse sektioner i denne rækkefølge:

```markdown
# Evidensbaseret genimport — vision og værdigrundlag

**Myndighed:** Autoritativt værdigrundlag for DAA-import og -genimport
**Scope:** Årbøger, kildebevaring, fortolkning, identitetsafstemning, promotion og publicering

## Vision
## Bindende principper
## Hvad visionen betyder for udvikling
## Ikke-mål
## Definition af succes
## Ændringsmyndighed
```

`## Vision` skal fastholde følgende ordlydsnære løfter fra det godkendte design:

- hver årbog er sin egen historiske stemme;
- import er en kontrolleret bevægelse fra original kilde over observation og fortolkning til menneskelig godkendelse og publicering;
- automatik må foreslå og kontrollere, men ikke skjule tvivl;
- én fysisk person kan have mange særskilte kildeoptrædener uden at blive duplikeret i den kanoniske model;
- en ny udgave skal bruge den fælles metode og en lille profil, ikke en parallel permanent arkitektur;
- alle meningsbærende oplysninger skal bevares, så nye klassifikationer normalt ikke kræver ny OCR eller grundudtræk;
- historisk troværdighed, redaktionel håndterbarhed, reproducerbarhed og læserværdi er fælles succeskriterier.

`## Bindende principper` skal mindst indeholde: originalen er uforanderlig; udsagn, fortolkning og afgørelse er forskellige; ingen evidens uden anker; ingen tavse tab; ingen tvungen sikkerhed; source record er ikke personidentitet; kildetekster flettes ikke; kanonisk model er konservativ; privat og uafklaret er fail-closed skjult; permanente fælles overflader er editionsneutrale.

`## Ikke-mål` skal afvise: perfekt OCR som succeskriterium; automatisk facit; strukturering af alt som kanonisk data; intern perfektion af 1939 som erstatning for en generel metode; mange tests eller et sikkert batch-run som eneste færdigbevis.

`## Ændringsmyndighed` skal sige, at kun projektejerens udtrykkelige beslutning må ændre dokumentet, og at ændringen samtidig registreres i `docs/decisions.md`.

- [ ] **Step 3: Opret `roadmap.md` med én aktiv stopport og den bindende rækkefølge**

Dokumentet skal have:

```markdown
# Evidensbaseret genimport — styrende roadmap

**Myndighed:** Autoritativ prioritering for genimportprogrammet
**Status:** Ét aktivt programmål ad gangen

## Aktivt programmål
## Styrende rækkefølge
## Adgangskrav til nye planer
## Modenhedstilstande
## Kontrollerede afbrydelser
## Hvad der er parkeret
## Ændringsmyndighed
```

Det aktive mål er: afslut C3 ved den planlagte samlede integration, disposable rehearsal og stop før produktion. Stopporten er et dokumenteret `READY_FOR_PRODUCTION_GO` eller en fail-closed blocker; den giver ikke i sig selv produktions-GO.

Den efterfølgende rækkefølge skal være:

1. narrativer knyttes entydigt til konkret source record (#152);
2. permanente writer-/batchmekanismer generaliseres (#153);
3. 2018-20 får fase A-ækvivalent provenance (#149);
4. den fælles fortolkningskæde og klausulgranularitet færdiggøres (#147/#148);
5. placement/membership og én identitetsvej konsolideres (#150/#151);
6. kæden køres ende-til-ende på begge referenceudgaver;
7. en tredje årbog beviser, at kun en lille profil og dokumenterede vokabularudvidelser kræves.

Adgangskravene til nye planer er de seks felter fra designets §5. Modenhedstilstandene er eksakt `specificeret`, `isoleret implementeret`, `integreret ende-til-ende`, `produktionsverificeret`. Spor H og M samt nye 1939-undtagelsesfaser markeres som parkerede, medmindre de kræves af det aktive mål eller en udtrykkelig beslutning.

- [ ] **Step 4: Kør fokuseret dokumentverifikation**

```bash
test -f docs/evidensbaseret-genimport/vision.md
test -f docs/evidensbaseret-genimport/roadmap.md
rg -n "én fysisk person|Ingen evidens uden anker|Ingen tavse tab|Ikke-mål|Ændringsmyndighed" docs/evidensbaseret-genimport/vision.md
rg -n "C3|#152|#153|#149|#147/#148|#150/#151|tredje årbog|produktionsverificeret" docs/evidensbaseret-genimport/roadmap.md
git diff --check
```

Expected: alle kommandoer exit 0; visionen indeholder ingen driftfølsomme produktionsrækker; roadmapet har præcis ét aktivt programmål.

- [ ] **Step 5: Commit Task 1**

```bash
git add docs/evidensbaseret-genimport/vision.md docs/evidensbaseret-genimport/roadmap.md
git commit -m "docs(genimport): fastlæg vision og roadmap"
```

---

### Task 2: Opret den tekniske målarkitektur

**Files:**

- Create: `docs/evidensbaseret-genimport/teknisk-maalarkitektur.md`

**Interfaces:**

- Consumes: `vision.md` og `roadmap.md` fra Task 1 samt den godkendte designspecifikation.
- Produces: en stabil, teknisk oversættelse, som implementeringsplaner skal argumentere imod uden at kopiere levende DDL eller dagsstatus.

- [ ] **Step 1: Verificér at målarkitekturen mangler**

```bash
test -f docs/evidensbaseret-genimport/teknisk-maalarkitektur.md
```

Expected: FAIL, fordi filen endnu ikke findes.

- [ ] **Step 2: Skriv målarkitekturens faste struktur**

Opret filen med disse sektioner:

```markdown
# Evidensbaseret genimport — teknisk målarkitektur

**Myndighed:** Autoritativ teknisk retning; levende kode og schema er source of truth for aktuelle detaljer

## Formål og afgrænsning
## Den fælles ende-til-ende-kæde
## Fælles motor og udgavespecifik profil
## Identiteter og kildeoptrædener
## Observation, fortolkning og promotion
## Narrativer og kildeversioner
## Redaktionel afgørelse og audit
## Gater og tilstandsforløb
## Genkørsel, stale beslutninger og fortrydelse
## Kanonisk model og offentlig projektion
## Bevis for generalisering
## Overgang fra legacy og parallelle workflows
## Tekniske ikke-mål
## Ændringsmyndighed
```

- [ ] **Step 3: Beskriv den fælles kæde og ansvarsgrænser uden levende implementationstal**

`## Den fælles ende-til-ende-kæde` skal beskrive disse trin og deres kontrakter:

```text
bibliografisk source
  -> uforanderlige renditions
  -> fysiske occurrences og menneskeligt accepterede source records
  -> klausulobservationer og mentions
  -> source personas og identitetskandidater
  -> proposed interpretations
  -> menneskelig afgørelse
  -> promotion til eksisterende eller nye kanoniske mål
  -> særskilt publiceringsbeslutning
  -> offentlig læseprojektion med kildehenvisning
```

For hvert trin skal dokumentet angive: input, bevaret identitet/provenance, tilladte beslutninger, fail-closed udgang og næste gate. `record_key` må aldrig beskrives som personidentitet; én source persona har højst ét aktivt kanonisk mål, mens én kanonisk person kan have mange source personas og records.

Fælles motor skal eje: identiteter, hashes/manifester, versions- og eventhistorik, kontraktvalidering, reviewtilstande, promotion, publication gates, batchaudit og reversering. En udgaveprofil må eje: sideudvalg, renditionvalg, layoutgrammatik, header-/postgenkendelse, udgavespecifik normalisering og dokumenterede vokabularafvigelser. Private arbejdsartefakter må være editionsnavngivne; permanente databaseoverflader og fælles workflows må ikke være det uden undtagelsesbeslutning.

- [ ] **Step 4: Beskriv gater, generaliseringsbevis og legacy-overgang**

Dokumentér disse gater i rækkefølge: source/rendition gate; boundary/record gate; observation/coverage gate; interpretation gate; identity gate; promotion gate; publication gate; apply/reversal gate.

Generalisering er først bevist, når:

- både 2018-20 og 1939 bruger samme kæde;
- en tredje årbog kan tilføjes uden nye permanente editionsnavngivne overflader;
- kun profil, kontrolleret vokabular og dokumenterede mappingregler ændres;
- redaktøren bruger én varig beslutningsvej;
- publiceret resultat kan spores tilbage og reproduceres eller reverseres.

Legacy-overgangen skal sige, at den gamle loader og lokale 1939-veje ikke udvides som parallel målarkitektur. Hver udfases først, når den fælles vej har paritet, eksplicit disposition for legacy-rækker og et grønt ende-til-ende-bevis.

- [ ] **Step 5: Kør målarkitekturens kontraktchecks**

```bash
rg -n "bibliografisk source|uforanderlige renditions|source persona|proposed interpretations|promotion|publiceringsbeslutning|offentlig læseprojektion" docs/evidensbaseret-genimport/teknisk-maalarkitektur.md
rg -n "source/rendition gate|boundary/record gate|observation/coverage gate|identity gate|apply/reversal gate" docs/evidensbaseret-genimport/teknisk-maalarkitektur.md
rg -n "tredje årbog|permanente databaseoverflader|parallel målarkitektur|Ændringsmyndighed" docs/evidensbaseret-genimport/teknisk-maalarkitektur.md
git diff --check
```

Expected: alle kommandoer exit 0; dokumentet indeholder ingen aktuelle prod-rækketal, task-checkboxes eller detaljerede SQL-signaturer.

- [ ] **Step 6: Commit Task 2**

```bash
git add docs/evidensbaseret-genimport/teknisk-maalarkitektur.md
git commit -m "docs(genimport): beskriv teknisk målarkitektur"
```

---

### Task 3: Opret et ærligt, dateret statussnapshot

**Files:**

- Create: `docs/evidensbaseret-genimport/status.md`

**Interfaces:**

- Consumes: current worktree through `cc9d7d5`, design commit `b0d3e19`, afvigelsesvurderingen fra 2026-08-22, den aktuelle C3-plan og Git-status ved execution.
- Produces: det eneste autoritative korte svar på programmets aktuelle modenhed og næste tilladte arbejde.

- [ ] **Step 1: Frys det kodegrundlag, statussnapshotet vurderer**

```bash
git status --short --branch
git log -1 --format='%H %cs %s' cc9d7d5
git log --oneline --reverse 2f64b7b..cc9d7d5
```

Expected: worktreet er rent ved taskstart; `cc9d7d5` findes og de viste commits dokumenterer C3-implementeringen efter afvigelsesvurderingen. Hvis senere funktionelle commits allerede er landet, udvid evidensgrundlaget og skriv deres eksakte commitinterval i status i stedet for at kalde `cc9d7d5` aktuelt.

- [ ] **Step 2: Skriv statusdokumentets faste struktur**

```markdown
# Evidensbaseret genimport — aktuel status

**Verificeret:** 2026-08-25
**Kodegrundlag:** `cc9d7d5` for funktionel C3-implementering; senere dokumentationscommits ændrer ikke den funktionelle klassifikation
**Produktionsstatus:** Ikke genverificeret i denne dokumentationsopgave; seneste anvendte måling er dateret 2026-08-22

## Samlet dom
## Aktivt programmål og stopport
## Modenhed pr. værdikædeled
## Væsentlige leverancer
## Fundament uden fuld anvendelse
## Åbne blokeringer
## Næste tilladte arbejde
## Parkeret arbejde
## Bevisgrundlag og friskhed
## Opdateringsregel
```

- [ ] **Step 3: Klassificér modenheden uden at udlede live produktionsstatus**

`## Samlet dom` skal sige:

- værdigrundlag og generelt fundament: stærkt;
- 1939-proveniens og narrativpublicering: væsentlig delleverance;
- fælles observation → fortolkning → identitet → promotion → publicering: ikke integreret ende-til-ende;
- fremtidig årbogsskabelon: ikke færdig og samlet NO-GO som generel leverance.

`## Modenhed pr. værdikædeled` skal bruge en tabel med de fire eksakte tilstande. Mindsteklassifikation:

- source/rendition og 1939-recordproveniens: mindst isoleret implementeret; produktionspåstande dateres 2026-08-22;
- klausulgranularitet: specificeret eller isoleret implementeret, ikke ende-til-ende;
- extractor-runner/modelkald: specificeret; `evidence_extract.py` kalder bevidst ingen model;
- proposed-ingest/promotion: isoleret implementeret fundament; ikke integreret;
- source-persona/webkø: isoleret implementeret; den virkelige 1939-vej er parallel;
- placement/membership: isoleret skema/fundament; ikke datavej;
- 2018-20 provenance: specificeret; ikke gennemført;
- C3: isoleret implementeret langt fremme; integration/rehearsal/production stop ikke dokumenteret færdig;
- tredje-årbogsprøve: specificeret.

`## Næste tilladte arbejde` må kun være C3 Task 9's resterende integration, disposable rehearsal og stop før produktion. Det må ikke give produktions-GO eller åbne `[NY]`, C1, C2 eller nye specialfaser.

`## Opdateringsregel` skal kræve et nyt evidensafstemt snapshot ved afslutningen
af en roadmapfase og før en ny genimportplan, hvis gren, kode eller
produktionsforhold har ændret sig væsentligt.

- [ ] **Step 4: Verificér statusens ærlighed og friskhedsmarkører**

```bash
rg -n "Verificeret:|Kodegrundlag:|Ikke genverificeret|2026-08-22|ikke integreret ende-til-ende|NO-GO|Næste tilladte arbejde" docs/evidensbaseret-genimport/status.md
rg -n "specificeret|isoleret implementeret|integreret ende-til-ende|produktionsverificeret" docs/evidensbaseret-genimport/status.md
rg -n "evidence_extract.py|project_evidence.R|C3|2018-20|tredje" docs/evidensbaseret-genimport/status.md
git diff --check
```

Expected: alle checks exit 0; ethvert produktionstal har en dato eller er udeladt; status hævder ikke, at C3 er rehearsed eller produktionsegnet.

- [ ] **Step 5: Commit Task 3**

```bash
git add docs/evidensbaseret-genimport/status.md
git commit -m "docs(genimport): frys aktuelt statussnapshot"
```

---

### Task 4: Gør styringsgrundlaget obligatorisk synligt for Claude og Codex

**Files:**

- Modify: `CLAUDE.md`
- Create: `AGENTS.md`
- Modify: `.claude/skills/daa-extract/SKILL.md`
- Modify: `docs/README.md`

**Interfaces:**

- Consumes: de fire autoritative dokumenter fra Tasks 1-3.
- Produces: ens scope, læserækkefølge og plan-gate i alle menneske-/LLM-indgange.

- [ ] **Step 1: Skriv den forventede fælles instruktionskontrakt ned før ændring**

Den samme kontrakt skal kunne genfindes i alle tre LLM-indgange:

```text
Scope: DAA-import/genimport, source records/personas, fortolkning, identitetsafstemning, promotion og importpublicering.
Læs: vision -> roadmap -> teknisk målarkitektur -> status.
Før plan/implementering: angiv roadmapmål, værdikædeled, leverancetype, bruger-/redaktørværdi, færdigbevis og workflow der erstattes.
Ingen omprioritering eller ny permanent editionsnavngiven overflade uden beslutning.
Historiske specs, planer, reviews og changelog er historik, ikke aktuel programstatus; levende kode/schema afgør driftede tekniske detaljer.
```

Kør før ændring:

```bash
test -f AGENTS.md
rg -n "evidensbaseret-genimport/vision.md" CLAUDE.md .claude/skills/daa-extract/SKILL.md docs/README.md
```

Expected: `test -f AGENTS.md` eller `rg` fejler.

- [ ] **Step 2: Tilføj en kort, scope-afgrænset sektion i `CLAUDE.md`**

Indsæt efter datamodellens invarianter og før generelle faldgruber:

```markdown
## Evidensbaseret genimport — bindende styringsgrundlag

Ved arbejde med DAA-import/genimport, source records/personas, fortolkning,
identitetsafstemning, promotion eller importpublicering: læs først, i rækkefølge,
`docs/evidensbaseret-genimport/vision.md`, `roadmap.md`,
`teknisk-maalarkitektur.md` og `status.md`.

Før en plan eller implementering skal opgaven kobles til roadmapmål,
værdikædeled, leverancetype, redaktionel/læserrettet værdi, færdigbevis og det
workflow den erstatter. Omprioritér ikke roadmapet, og opret ikke nye permanente
editionsnavngivne overflader uden en beslutning i `docs/decisions.md`.

Historiske specs, planer, reviews og changelog er historik, ikke aktuel
programstatus. Levende kode og schema er source of truth for tekniske detaljer,
der kan være ændret siden statussnapshotet.
```

Tilføj ikke dagsstatus eller issue-numre i `CLAUDE.md`.

- [ ] **Step 3: Opret rod-`AGENTS.md` med identisk kontrakt og eksplicit scope**

Filen skal gøre klart, at reglerne kun gælder genimport-/årbogsarbejde og ikke
andre projektspor. Den skal pege på de fire dokumenter med repo-relative stier,
bevare brugerens konkrete instruktioner som højere myndighed og sige, at
levende kode/schema overtrumfer et statussnapshot for driftede tekniske detaljer.
Den må ikke gentage hele visionen.

- [ ] **Step 4: Tilføj styringsgrundlaget før operationelle trin i `/daa-extract`-skillen**

Indsæt efter `# DAA-udtræk: stamtavle-PDF → evidensbaseret datamodel` og før
`## Formål og filosofi`:

```markdown
## Bindende styringsgrundlag før arbejde

Læs i rækkefølge:
1. `docs/evidensbaseret-genimport/vision.md`
2. `docs/evidensbaseret-genimport/roadmap.md`
3. `docs/evidensbaseret-genimport/teknisk-maalarkitektur.md`
4. `docs/evidensbaseret-genimport/status.md`

Skillens operationelle runbooks giver ikke selv roadmap- eller produktions-GO.
En ny plan skal opfylde roadmapets seks adgangskrav, før pipeline eller
udgavespecifikke undtagelsesspor udvides.
Historiske specs, planer og reviews er bevis og historik, ikke aktuel
programstatus; levende kode og schema afgør driftede tekniske detaljer.
```

- [ ] **Step 5: Opdatér dokumentationsindekset og fjern forældet myndighed**

I `docs/README.md`:

- tilføj de fire dokumenter øverst under `Læs disse først` med deres forskellige roller;
- flyt afvigelsesvurderingen til historisk/review-kontekst og beskriv `status.md` som aktuelt statusorakel;
- ret `plan-1939-produktionsklar.md` til tydeligt at være historisk, uden den forældede påstand om at 1939-publicering er pauset indtil ny OCR;
- behold `database-current-state.md` som autoritet for live prod, men kræv frisk kontrol ved driftfølsomme spørgsmål.

- [ ] **Step 6: Verificér fælles scope og læserækkefølge**

```bash
for f in CLAUDE.md AGENTS.md .claude/skills/daa-extract/SKILL.md; do rg -n "vision.md|roadmap.md|teknisk-maalarkitektur.md|status.md" "$f"; done
rg -n "roadmapmål|værdikædeled|færdigbevis|editionsnavngivne" CLAUDE.md AGENTS.md
for f in CLAUDE.md AGENTS.md .claude/skills/daa-extract/SKILL.md; do rg -n "historik, ikke aktuel programstatus|historik.*ikke aktuel programstatus" "$f"; done
rg -n "Aktuel status|teknisk målarkitektur|styrende roadmap|vision og værdigrundlag" docs/README.md
git diff --check
```

Expected: alle dokumenter findes i samme rækkefølge; scope er eksplicit i `AGENTS.md`; ingen indgang kopierer dagsstatus.

- [ ] **Step 7: Commit Task 4**

```bash
git add CLAUDE.md AGENTS.md .claude/skills/daa-extract/SKILL.md docs/README.md
git commit -m "docs(genimport): gør retningen obligatorisk for agenter"
```

---

### Task 5: Registrér styringsbeslutningen og verificér hele pakken

**Files:**

- Modify: `docs/decisions.md`
- Modify: `docs/changelog.md`
- Verify: all files from Tasks 1-4

**Interfaces:**

- Consumes: den færdige dokumentpakke og alle LLM-indgange.
- Produces: varig beslutningshistorik, dateret changelog og et samlet verifikationsbevis.

- [ ] **Step 1: Tilføj beslutningen øverst i `docs/decisions.md`**

Tilføj en sektion dateret 2026-08-25, som registrerer:

- model 2, den lagdelte styringsmodel, er valgt;
- de fire dokumenters roller og myndighed;
- vision/målarkitektur kræver udtrykkelig projektbeslutning;
- roadmaprækkefølge kræver begrundet beslutningspost;
- status er driftfølsomt snapshot, ikke kilde til stabile værdier;
- ét aktivt programmål og seks adgangskrav til nye planer;
- CI-håndhævelse er bevidst udskudt, indtil den manuelle model er afprøvet.

Henvis til designspecifikationen og de fire dokumenter; kopiér ikke visionsteksten.

- [ ] **Step 2: Tilføj en dokumentationspost øverst i `docs/changelog.md`**

Posten skal sige:

- dokumentpakken og LLM-indgangene er indført;
- værdigrundlag, roadmap, målarkitektur og status er adskilt;
- genimportarbejde har nu obligatorisk roadmapkobling;
- ingen kode, database eller produktion er ændret;
- det første snapshot gør C3-stopporten til aktivt mål og fastholder den generelle kæde som uafsluttet.

- [ ] **Step 3: Kør samlet placeholder- og myndighedskontrol**

```bash
rg -n '\b(TBD|TODO|FIXME|XXX)\b|___' docs/evidensbaseret-genimport CLAUDE.md AGENTS.md .claude/skills/daa-extract/SKILL.md docs/README.md docs/decisions.md docs/changelog.md
rg -n "Autoritativ|Myndighed|aktivt programmål|ændringsmyndighed" docs/evidensbaseret-genimport
rg -n "afvigelsesvurdering.*aktuel|plan-1939-produktionsklar.*Aktiv styringsplan" docs/README.md CLAUDE.md AGENTS.md
```

Expected: første kommando har ingen fund i de nye sektioner; sidste kommando har ingen fund. Eksisterende `TODO` uden for de ændrede sektioner i den lange skill skal rapporteres som baseline og må ikke omskrives til en ny fejl.

- [ ] **Step 4: Kontrollér alle relative Markdown-links i de ændrede dokumenter**

Kør denne read-only linkkontrol; den opretter ingen permanent scriptfil:

```bash
/usr/bin/python3 - <<'PY'
from pathlib import Path
import re
import sys

files = [Path(value) for value in (
    "CLAUDE.md",
    "AGENTS.md",
    ".claude/skills/daa-extract/SKILL.md",
    "docs/README.md",
    "docs/evidensbaseret-genimport/vision.md",
    "docs/evidensbaseret-genimport/roadmap.md",
    "docs/evidensbaseret-genimport/teknisk-maalarkitektur.md",
    "docs/evidensbaseret-genimport/status.md",
    "docs/decisions.md",
    "docs/changelog.md",
)]
pattern = re.compile(r"(?<!!)\[[^]]+\]\(([^)]+)\)")
missing = []
for source in files:
    text = source.read_text(encoding="utf-8")
    text_without_fences = re.sub(r"```.*?```", "", text, flags=re.DOTALL)
    for raw_target in pattern.findall(text_without_fences):
        target = raw_target.strip().split("#", 1)[0]
        if not target or target.startswith(("http://", "https://", "mailto:")):
            continue
        if target.startswith("<") and target.endswith(">"):
            target = target[1:-1]
        candidate = (source.parent / target).resolve()
        if not candidate.exists():
            missing.append(f"{source}: {raw_target} -> {candidate}")
if missing:
    print("\n".join(missing))
    sys.exit(1)
print(f"OK: lokale links kontrolleret i {len(files)} filer")
PY
```

Expected: nul manglende lokale targets i de nye eller ændrede links. Forudeksisterende døde links uden for den ændrede dokumentpakke rapporteres særskilt og ændres ikke i denne opgave.

- [ ] **Step 5: Gennemlæs pakken i den bindende rækkefølge og kontrollér specdækning**

Kontrollér eksplicit:

- vision indeholder alle løfter og ikke-mål fra design §3.1;
- roadmap indeholder hele rækkefølgen og seks adgangskrav;
- målarkitektur dækker hvert punkt i design §3.3;
- status indeholder alle minimumspunkter fra design §8 og ingen udateret live-påstand;
- alle fire LLM-/dokumentindgange viser samme rækkefølge;
- beslutningslog og changelog er historik, ikke kopier af autoritativt indhold;
- andre projektspor er udtrykkeligt uden for scope.

- [ ] **Step 6: Kør endelig Git-verifikation**

```bash
git diff --check
git status --short
git diff --stat HEAD~4..HEAD
```

Expected: `git diff --check` exit 0; status viser kun Task 5's to tilsigtede filer før commit; diffstat viser kun dokumentation og instruktioner, ingen SQL-, R-, Python- eller TypeScript-produktionskode.

- [ ] **Step 7: Commit Task 5**

```bash
git add docs/decisions.md docs/changelog.md
git commit -m "docs(genimport): registrér bindende styringsmodel"
```

- [ ] **Step 8: Rapportér afslutning uden at overdrive programstatus**

Rapportér de fem commits, alle verifikationskommandoer, eventuelle forudeksisterende link-/TODO-fund og et klart resultat:

```text
Dokumentstyringspakken: GO
Genimportens generelle ende-til-ende-leverance: fortsat NO-GO
Aktivt næste mål: C3 integration/rehearsal/stop før produktion
Produktionsændringer: ingen
```
