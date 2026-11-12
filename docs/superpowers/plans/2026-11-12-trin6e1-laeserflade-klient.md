# Trin 6e-1 — læserfladen i klienten: implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Personsidens fakta vises én gang pr. oplysning i den valgte udgaves ord, med den anden udgave som note (visning C), og biografivælgeren åbner på den fulde post — uden DDL.

**Architecture:** Al logik ligger DOM-fri i `packages/core` (lighed, udgave pr. række, fakta pr. udgave, vælger, etiketfilter). Web-laget henter de samme RPC'er som i dag plus ét anon-opslag i `citation` og giver core udgaveoplysningerne fra modellen; `DetailPanel`/`PersonFakta` renderer kun.

**Tech Stack:** TypeScript, React (Vite), vitest, Playwright; npm workspaces (`@daa/core`, `web`).

**Spec:** `docs/superpowers/specs/2026-11-12-trin6e-laeserflade-design.md` (godkendt 2026-11-12). Læs §3, §4, §5.1-5.5, §5.8 og §8. 6e-2 (§5.6-5.7: DDL, ceremoni, koordinater, B6, linjer, »Optræder i Aarbogen«, »Kilde i Aarbogen«) får sin egen plan efter 6e-1 er i prod.

## Global Constraints

- Ingen DDL, ingen dataskrivning, ingen ændring af RPC'er (spec §4: 6e-1 er klient-only). Supabase-kald kun som anon/læsning.
- Mobilen (`mobile/`) røres ikke (spec §4 ikke-mål).
- `packages/core` forbliver DOM-/RN-fri; nye moduler eksporteres fra `packages/core/src/index.ts`.
- Tekster (ordret): `✓ også i <udgave>`, `<udgave> skriver: <v1>; <v2>`, `Kun i <udgave>`, `Ingen biografi fra denne udgave`. `<udgave>` = `source.udgave` (»DAA 1939«, »DAA 2018-20«).
- Ingen `record-<uuid>` og ingen `legacy-source:` som synlig tekst i læseren (spec §4 anti-mål, §5.6 »indtil 6e-2«).
- Konservativ lighed: ved tvivl ikke ens (spec §5.4). En række bekræfter aldrig sig selv (spec §5.1).
- Arbejdsmapperne `work/`, `work_1939_stamtavle/`, `work_presens/` og `~/.private` må ikke læses; stikprøve-arket med værdier skrives til scratchpad, ikke repo.
- Hele CI's node-job køres lokalt før PR: `npm run test -w @daa/core && npm run typecheck -w @daa/core && npm run test -w web && npm run build -w web && npm --workspace mobile exec -- tsc --noEmit && npm test -w mobile`.
- Commits: Conventional Commits på dansk, ét pr. task. PR som `--draft`.

## Afvigelse fra spec'en (meldt til projektejeren)

- **Hovedets linjer følger vælgeren** (spec §4's 6e-1-række) flyttes til 6e-2: linjenøglerne i `model.lineage` er kanoniske på tværs af udgaver og bærer ingen kilde, så filtreringen kræver 6e-2's placement-koordinater. 6e-1 viser hovedets linjer som i dag.
- Spec'ens »plan-Task 0« (måling og stikprøve) er her **Task 5**, fordi den kører den færdige core-kode mod stand-in.

## Review Focus

1. **Person med kun én udgave** (de fleste): ingen vælger, samme fakta som i dag, blot med sammenlagte dubletter og uden dobbelt værdi — ingen noter. Test i Task 3 og Task 7.
2. **Samme række via flere medlems-id'er** (RPC'en kaldes med alle komponentens id'er): dubletter fjernes som i dag (`JSON.stringify`-nøgle). Test i Task 3.
3. **Personrække uden ekstern nøgle med citationer til to udgaver**: vises i alle udgaver, indgår aldrig i en note. Test i Task 3.
4. **Værdien »—« eller kun tegnsætning/blanktegn**: ingen linje, ingen note, ingen »Kun i«. Test i Task 1 og Task 3.
5. **Ingen biografi og ingen fakta** for personen: intet vælgerområde, ingen »Ingen biografi«-tekst. Test i Task 4 og Task 7.

---

### Task 1: Lighedsreglen og dobbelt værdi

**Files:**
- Create: `packages/core/src/factEquality.ts`
- Modify: `packages/core/src/personFacts.ts:47-50` (`factValue`)
- Modify: `packages/core/src/index.ts`
- Test: `packages/core/src/__tests__/factEquality.test.ts`, `packages/core/src/__tests__/personFacts.test.ts`

**Interfaces:**
- Produces:
  - `export const DATO_TYPER: ReadonlySet<string>` = `fødsel, dåb, død, begravelse`
  - `export const ENKELTVAERDI_TYPER: ReadonlySet<string>` = `navn, fødsel, dåb, død, dødsårsag, begravelse, adling, klosterindgang` (øvrige typer er flerværdi)
  - `export function erTomFaktaVaerdi(v: string): boolean`
  - `export function normaliserFaktaVaerdi(faktatype: string, v: string): string`
  - `export function faktaVaerdierEns(faktatype: string, a: string, b: string): boolean` (falsk hvis en af dem er tom)

- [ ] **Step 1: Skriv de fejlende tests** (`factEquality.test.ts`), præcis disse par:

```ts
const ens = (t: string, a: string, b: string) => faktaVaerdierEns(t, a, b);
expect(ens('fødsel', '21. april 1644', '21 April 1644')).toBe(true);
expect(ens('død', '21. juli 1708', '21 Juli 1708')).toBe(true);
expect(ens('død', '† 21. juli 1708', '21 Juli 1708')).toBe(true);
expect(ens('fødsel', '1.12.1700', '11.2.1700')).toBe(false);   // tegnsætning → mellemrum, ikke fjernet
expect(ens('fødsel', '1644?', '1644')).toBe(false);             // ? bevares
expect(ens('fødsel', 'ca. 1690', '1690')).toBe(false);
expect(ens('fødsel', 'ca. 1690', 'o. 1690')).toBe(true);        // fælles ord, ikke fjernet
expect(ens('død', '15. febr. 1878 på Pronstorf', '15. febr. 1878')).toBe(false); // sted kun på én side
expect(ens('titel', 'Greve', 'greve')).toBe(true);
expect(ens('navn', 'Ditlev', 'Detlef')).toBe(false);
expect(ens('dekoration', 'Kmhr.', 'Kammerherre')).toBe(false);
expect(erTomFaktaVaerdi('—')).toBe(true);
expect(erTomFaktaVaerdi(' .; ')).toBe(true);
expect(ens('begravelse', '—', '—')).toBe(false);
```

  I `personFacts.test.ts`: `it('viser vaerdi_tekst og date_raw én gang, når de er ens')` — række med `vaerdi_tekst: '15. febr. 1878.'`, `date_raw: '15. febr. 1878.'` giver `chosen.value === '15. febr. 1878.'`; forskellige værdier giver fortsat `'a, b'`.

- [ ] **Step 2: Kør og se dem fejle** — `npm run test -w @daa/core -- factEquality personFacts` → FAIL (modul mangler / dobbelt værdi).

- [ ] **Step 3: Implementér.** Datotyper: små bogstaver; `†`, `*`, `⚭` væk; `ca.`/`o.`/`omkr.`/`circa` → ordet `ca`; `s.a.`/`s. a.` → `sa`; `?` → ` ? `; danske og 1939-månedsnavne/-forkortelser → tal (jan|januar → 1 … dec|december → 12, inkl. `febr`, `sept`, `okt`); øvrig tegnsætning `[.,;:()/\-–]` → mellemrum; mellemrum samlet. Tekst: små bogstaver; bindestreg-/apostrofvarianter ens; tegnsætning → mellemrum; mellemrum samlet. `factValue`: udelad `date_raw`, når den efter `trim()` er lig `vaerdi_tekst`.

- [ ] **Step 4: Kør igen** — samme kommando → PASS.

- [ ] **Step 5: Commit** — `feat(core): lighedsregel for fakta på tværs af udgaver`

### Task 2: Filter for tekniske postetiketter

**Files:**
- Create: `packages/core/src/recordLabel.ts`
- Modify: `packages/core/src/personFacts.ts:52-62` (`factSource`), `packages/core/src/familieKilder.ts:75-77` (`kildeLinje`), `packages/core/src/index.ts`
- Test: `packages/core/src/__tests__/recordLabel.test.ts`, `personFacts.test.ts`, `familieKilder.test.ts`

**Interfaces:**
- Produces: `export function visbarPostEtiket(label: string | null | undefined): string | null` — `null` for tom/blank, for `/^record-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i` og for præfikset `legacy-source:`; ellers den trimmede etiket.

- [ ] **Step 1: Fejlende tests:** `visbarPostEtiket('record-07565168-b903-4444-9189-43d62d5c6ed6') === null`; `('legacy-source:3:II') === null`; `('V-1') === 'V-1'`; `('') === null`. `factSource` for en bundet række med `record_label` = record-uuid og `citation_label: 'DAA 1939, s. 541'` giver `label === 'DAA 1939, s. 541'` (ingen ` · `). `kildeLinje` med record-uuid giver `'Kilde: DAA 1939'`; med `'V-1'` uændret `'Kilde: DAA 2018-20 · V-1'`.
- [ ] **Step 2: Kør og se dem fejle** — `npm run test -w @daa/core -- recordLabel personFacts familieKilder` → FAIL.
- [ ] **Step 3: Implementér** og brug funktionen i `factSource` og `kildeLinje`.
- [ ] **Step 4: Kør igen** → PASS.
- [ ] **Step 5: Commit** — `feat(core): skjul tekniske postetiketter i læseren`

### Task 3: Fakta pr. udgave med noter

**Files:**
- Create: `packages/core/src/editionFacts.ts`
- Modify: `packages/core/src/index.ts`
- Test: `packages/core/src/__tests__/editionFacts.test.ts`

**Interfaces:**
- Consumes: `PublicPersonFactRow`, `PersonFactSource`, `PersonFactStatement` (personFacts.ts); Task 1's lighed; Task 2's etiketfilter (via `factSource`).
- Produces:

```ts
export type Udgave = { sourceId: string; label: string; aar: number | null };
export type UdgaveFaktaInput = {
  rows: PublicPersonFactRow[];
  udgaver: Udgave[];                              // kun source.slags = 'DAA-udgave'
  udgaveForPersonRaekke: Record<string, string>;  // person_id → sourceId fra ekstern nøgle
  fritekstKilde: Record<string, string[]>;        // assertion_id → alle citat_tekst for citationer uden source_id
  slukketEnighed?: ReadonlySet<string>;           // faktatyper uden »✓ også« (spec §5.4)
};
export type UdgaveNote =
  | { art: 'enig'; udgave: Udgave }
  | { art: 'skriver'; udgave: Udgave; vaerdier: string[] };
export type UdgaveFaktaLinje = {
  noegle: string; faktatype: string; vaerdi: string; kilder: PersonFactSource[];
  omstridt: boolean; andre: PersonFactStatement[]; noter: UdgaveNote[];
};
export type KunIUdgave = { udgave: Udgave; faktatype: string; vaerdier: string[] };
export type UdgaveFaktaVisning = { linjer: UdgaveFaktaLinje[]; kunI: KunIUdgave[] };
export function udgaveForRaekker(input: UdgaveFaktaInput): Record<string, string | null>;
export function udgaverMedFakta(input: UdgaveFaktaInput): string[];
export function byggUdgaveFakta(input: UdgaveFaktaInput, valgt: string | null): UdgaveFaktaVisning;
```

Regler (spec-§ i parentes):
- **Rækkens udgave** (§5.1): ekstern nøgle; ellers den ene DAA-udgave, som rækkens citationer (`source_id` på dens faktarækker) peger på; ellers (ingen eller flere) `null` = vis i alle udgaver, aldrig i noter.
- **Vist påstand pr. faktum** (§5.2): `chosen`, når den er udgavens egen — `record_ref` sat, `source_id` = rækkens udgave, eller `source_id` null og **alle** tekster i `fritekstKilde[assertion_id]` nævner netop den udgaves `label` og ingen anden udgaves (tom liste eller modstrid → ikke egen). Ellers den første af faktummets ikke-valgte påstande, der er udgavens egen (bundet før import, lavest `assertion_id`); findes ingen, `chosen` som i dag, og faktummet indgår ikke i noter. `chosen = null` (omstridt): vises som i dag; i andre udgavers noter indgår alle dets udsagn som »skriver«.
- **Sammenlægning** (§5.2): linjer i den valgte udgave med samme `faktatype` og ens værdi (Task 1) bliver én linje; `kilder` = foreningen (dubletter efter `label` fjernet).
- **Noter** (§5.3) mod hver anden udgave med viste værdier af typen, nyeste `aar` først. Kun den valgte udgaves *udgaveegne* linjer får noter (et redaktørfaktum vist »som i dag« får ingen). Type i `slukketEnighed` → altid `skriver` med den anden udgaves forskellige viste værdier, både enkelt- og flerværdi. Ellers enkeltværdi → `enig` kun hvis **alle** den anden udgaves viste værdier er ens med linjen; ellers `skriver` med dem alle. Flerværdi → `enig` hvis en af dens værdier er ens; ellers ingen note.
- **Invariant — ingen oplysning forsvinder:** hver vist værdi i en anden udgave optræder i en note eller i `kunI`. Alt, der ikke er dækket af en note (uparrede flerværdier, typer den valgte udgave ikke har, typer hvor den valgte kun har et redaktørfaktum), går til `kunI`.
- **Tomme værdier** (§5.4) og `FAKTA_UDELADT` vises aldrig.
- **Rækkefølge:** som `buildPersonFacts` (typeorden, `date_min`, `fact_id`).
- `valgt = null` → alle rækker som én udgave uden noter.

- [ ] **Step 1: Fejlende tests** — fixtures bygget med `row()`-hjælperen fra `personFacts.test.ts` (kopier den):
  - `it('Conrad: 2018-20 viser bøgernes ord med noter')` — person 392 (ext 1): navn-faktum med valgt redaktørpåstand `Conrad` (`source_id: null`, fritekst `'Dansk Adels Aarbog – DAA 1939'`) og ikke-valgt `Conrad de Reventlow` (`source_id: 1`); person 255 (ext 1) og 392 hver med titel `greve`/`Greve` (source 1, bundet: `record_ref` sat, `record_label` `III-58` hhv. `V-1`, `citation_label` `DAA 2018-20, s. 137` hhv. `s. 201-202`); fødsel `21. april 1644` på 392 (source 1); person 1198 (ext 3) bundet navn `Conrad Reventlow`, titel `Greve`, fødsel `21 April 1644`, død `21 Juli 1708` (`record_ref` sat, `record_label` record-uuid, `citation_label: 'DAA 1939, s. 541'`); død `21. juli 1708` på 392. Forvent for `valgt='1'`: navn-linje `vaerdi === 'Conrad de Reventlow'` med `noter = [{art:'skriver', udgave: DAA 1939, vaerdier:['Conrad Reventlow']}]`; præcis én titel-linje med to kilder og `enig`-note; fødsel og død `enig`; `kunI` tom.
  - `it('Conrad: 1939 viser 1939's ord og 2018-20 som note')` — `valgt='3'`: navn `Conrad Reventlow` med `skriver` `['Conrad de Reventlow']`; ingen kildelabel indeholder `record-`.
  - `it('OCR-rettelse med fritekst for samme udgave vises som udgavens egen')` — ext 3-række, valgt `Ditlev Christian` (`source_id` null, fritekst `'Dansk Adels Aarbog – DAA 1939, 521'`), ikke-valgt bundet OCR-tekst → `vaerdi === 'Ditlev Christian'`.
  - `it('redaktørfaktum uden udgaveegen påstand vises som i dag og uden noter')` — kun én påstand, fritekst `'(kilde mangler)'`.
  - `it('enkeltværdi: flere forskellige værdier i den anden udgave giver skriver a; b, aldrig ✓')` — 2018-20 død `1850`; 1939 to personrækker med død `1850` og `1851` → `skriver` med `['1850','1851']`.
  - `it('flerværdi: uparret titel går til kunI')`, `it('type kun i den anden udgave går til kunI')`.
  - `it('slukketEnighed gør enig til skriver for typen')` — både for `død` (enkelt) og `titel` (flerværdi).
  - `it('redaktørfaktum i valgt udgave: den anden udgaves egen værdi går til kunI')` — 2018-20 død kun som redaktørfaktum (`(kilde mangler)`), 1939 bundet død `1708` → `kunI` indeholder død `1708`.
  - `it('fritekst: flere citationer med modstridende udgaver → ikke egen, uanset rækkefølge')`.
  - `it('invariant: hver anden udgaves viste værdi er i en note eller kunI')` — kør over alle fixtures i filen.
  - `it('ægtefælle uden ekstern nøgle får udgave fra citationerne')`; `it('række med citationer til to udgaver vises i alle og indgår ikke i noter')` (Review Focus 3).
  - `it('omstridt uden valgt påstand: alle udsagn som skriver i den anden udgave')`.
  - `it('samme række fra flere medlems-id'er tælles én gang')` (Review Focus 2); `it('én udgave: ingen noter, dubletter lagt sammen')` (Review Focus 1); `it('tom værdi giver hverken linje, note eller kunI')` (Review Focus 4).
- [ ] **Step 2: Kør og se dem fejle** — `npm run test -w @daa/core -- editionFacts` → FAIL.
- [ ] **Step 3: Implementér** `editionFacts.ts` efter reglerne ovenfor; genbrug `factValue`/`factSource` fra `personFacts.ts` (eksportér dem internt, ikke fra index).
- [ ] **Step 4: Kør igen + typecheck** — `npm run test -w @daa/core && npm run typecheck -w @daa/core` → PASS.
- [ ] **Step 5: Commit** — `feat(core): fakta pr. udgave med noter om den anden udgave`

### Task 4: Udgavevælgeren

**Files:**
- Create: `packages/core/src/editionSelector.ts`
- Modify: `packages/core/src/index.ts`
- Test: `packages/core/src/__tests__/editionSelector.test.ts`

**Interfaces:**
- Consumes: `BioSourceVersion`, `BioSourceVersionV2` (bioVersions.ts), `Udgave` (Task 3), `visbarPostEtiket` (Task 2).
- Produces:

```ts
export type UdgaveChip =
  | { art: 'post'; sourceId: string; label: string; version: BioSourceVersion }
  | { art: 'udgave'; sourceId: string; label: string };  // udgave med fakta, uden biografi
export type UdgaveVaelger = { chips: UdgaveChip[]; standard: number; form: 'ingen' | 'chips' | 'skift' };
export function byggUdgaveVaelger(versioner: BioSourceVersion[], udgaver: Udgave[], udgaverMedFakta: string[]): UdgaveVaelger;
```

Regler (§5.5, afgørelse 11): én chip pr. biografipost (`label` = `sourceLabel` + ` · <visbar postetiket>` eller ` · overgangsdata` som i dag; uden visbar etiket kun `sourceLabel`); én `udgave`-chip pr. udgave i `udgaverMedFakta` uden post. Versionens udgave: `sourceId` (v2), ellers `udgaver` slået op på `label === sourceLabel`. Chips ordnes nyeste `aar` først, inden for udgaven længste `narrativeText` først. `standard` = første chip. `form`: ≤1 chip → `ingen`; ingen `post`-chips → `skift`; ellers `chips`.

- [ ] **Step 1: Fejlende tests:** `it('Conrad: åbner på V-1, III-58 er stadig en chip')` (V-1 lang, III-58 kort, begge kilde 1; 1939-post kilde 3) → `chips[0]` er V-1, III-58 findes, 1939 sidst. `it('1939 med fakta men uden biografi får en udgave-chip')`. `it('én chip giver form ingen')`. `it('ingen biografier og to udgaver giver form skift')`. `it('ingen biografi og ingen fakta giver ingen chips')` (Review Focus 5). `it('postetiket record-uuid vises ikke i chippen')`.
- [ ] **Step 2: Kør og se dem fejle** — `npm run test -w @daa/core -- editionSelector` → FAIL.
- [ ] **Step 3: Implementér.**
- [ ] **Step 4: Kør igen** → PASS.
- [ ] **Step 5: Commit** — `feat(core): udgavevælger med standard på den fulde post`

### Task 5: Måling og stikprøve på stand-in (spec'ens »plan-Task 0«)

**Files:**
- Create: `tools/maal-6e1/maal.ts`
- Create: `docs/evidensbaseret-genimport/laeserflade-6e1-maaling.md` (kun tal)

**Interfaces:**
- Consumes: `udgaveForRaekker`, `udgaverMedFakta`, `byggUdgaveFakta` (Task 3), `byggUdgaveVaelger` (Task 4).
- Produces: værdien af `SLUKKET_ENIGHED` (Task 6) og projektejerens dom over stikprøven.

- [ ] **Step 1: Skriv scriptet.** Kørsel: `PGDATABASE=daa5ab_ddl_standin_20261111191901_slut npx tsx tools/maal-6e1/maal.ts --ark <scratchpad>/6e1-stikproeve.html`. Kun læsning via `psql -XAt` (`--csv`/JSON): offentlige personer, afklarede `samme_som`-kanter (komponenter som klientens foldning), `public_person_source_coordinates()` (udgave pr. række), DAA-kilder, `public.public_person_facts(<komponentens id'er>)` pr. komponent, `citation.citat_tekst` for valgte påstande uden `source_id`. For hver komponent og hver udgave: `byggUdgaveFakta`.
- [ ] **Step 2: Kør og aflæs** — stdout skal vise: pr. faktatype antal linjer, `enig`, `skriver`, `kunI`; antal komponenter pr. vælgerform (`ingen`/`chips`/`skift`); de 17 redaktørpåstande fordelt på »udgavens egen« / »bøgernes ord vist« / »som i dag«; antal `record-` i alle kildelabels (forventet 0).
- [ ] **Step 3: Stikprøven.** Arket viser 40 tilfældige `enig`-par (fast seed `6e1`), pr. par: komponent, faktatype, begge rå værdier med udgave og side. Tjek at intet par er falsk; send arket til projektejeren (`SendUserFile`) og vent på dom. Et falsk par → typen i `SLUKKET_ENIGHED`, reglen rettes i Task 1, ny stikprøve for typen.
- [ ] **Step 4: Skriv tallene** (ingen værdier, ingen navne) i `laeserflade-6e1-maaling.md` med stand-in-navn og dato.
- [ ] **Step 5: Commit** — `docs(6e): måling og stikprøve for læserfladens fakta` (scriptet + tal-filen; arket forbliver i scratchpad).

### Task 6: Web-datalaget giver core udgaveoplysningerne

**Files:**
- Modify: `web/src/data/model.ts:73-79` (source-select får `aar`), `:150-175` (model-felter)
- Modify: `packages/core/src/types.ts:167` (`Model` får de to felter som **valgfrie**, så mobilen kompilerer uændret), `web/src/data/public.ts:178-182, 210-320`
- Modify: `web/src/Folgesvend.tsx:185-188`, `web/src/components/PresensView.tsx:302`, `web/src/data/types.ts:68` (`RawSource` får `aar`)
- Modify (fixtures): `web/src/components/__tests__/DetailPanel.familieKilder.test.tsx:27` og andre typede `PersonDetailData`-fixtures (`faktaInput: null`)
- Create: `web/src/data/udgaver.ts` (`SLUKKET_ENIGHED`)
- Test: `web/src/data/__tests__/personDetail.udgaver.test.ts`

**Interfaces:**
- Consumes: `Udgave`, `UdgaveFaktaInput` (Task 3).
- Produces:
  - `Model.udgaver?: Udgave[]` (kilder med `slags === 'DAA-udgave'`, `label = udgave`, `aar`) og `Model.udgaveForPersonRaekke?: Record<string, string>` (fra koordinatrækkernes `person_id`/`source_id`).
  - `fetchPersonDetail(id, memberIds?, hentKilder?, udgaveKontekst?: { udgaver: Udgave[]; udgaveForPersonRaekke: Record<string, string> })`.
  - `PersonDetailData.faktaInput: UdgaveFaktaInput | null` (null ved faktafejl; `facts`/`factsError` bevares for kompatibilitet), `PersonEstate.personId: string`. Godser deduplikeres på `(personId, gods-id)` i datalaget; først visningen (Task 7) deduplikerer på gods-id efter udgavefiltreringen.
  - `export const SLUKKET_ENIGHED: ReadonlySet<string>` i `udgaver.ts` (sættes efter Task 5).

- [ ] **Step 1: Fejlende tests** (mock `../../supabase` som `familySources.test.ts`): `it('henter citat_tekst kun for valgte påstande uden source_id')` — RPC-svar med én valgt `source_id: null`-række og én med kilde; forvent ét `citation`-opslag med netop det `assertion_id` og `faktaInput.fritekstKilde` sat. `it('fejl i citation-opslaget giver tom fritekstKilde, ikke faktafejl')`. `it('embede uden organisationsnavn ud over rollen vises kun som rollen')` (rolle `Greve`, org `greve` → `label === 'Greve'`). `it('samme gods fra to medlemmer i hver sin udgave bevares som to rækker med hver sin personId')`.
- [ ] **Step 2: Kør og se dem fejle** — `npm run test -w web -- personDetail.udgaver` → FAIL.
- [ ] **Step 3: Implementér.** Relationsselect får `subjekt_id`. Embede: `[rolle, org]` hvor `org` udelades, når den uden forskel på store/små bogstaver er lig `rolle`. Citation-opslag: `supabase.from('citation').select('assertion_id,citat_tekst').in('assertion_id', ids)` efter fakta-RPC'en, kun når `ids` ikke er tom.
- [ ] **Step 4: Kør igen + typecheck** — `npm run test -w web && npm run build -w web` → PASS.
- [ ] **Step 5: Commit** — `feat(web): udgaveoplysninger og redaktørens kildetekst til faktalæseren`

### Task 7: Persondetaljen viser visning C

**Files:**
- Modify: `web/src/components/DetailPanel.tsx:36-37, 146-181, 211-226, 245-253`
- Modify: `web/src/components/PersonFakta.tsx`
- Test: `web/src/components/__tests__/PersonFakta.test.tsx`, `web/src/components/__tests__/DetailPanel.udgaver.test.tsx`, `web/e2e/person-facts.spec.ts`

**Interfaces:**
- Consumes: `byggUdgaveVaelger`, `udgaverMedFakta`, `byggUdgaveFakta` (Task 3-4), `PersonDetailData.faktaInput`, `PersonEstate.personId`, `Model.udgaver`, `Model.udgaveForPersonRaekke`, `SLUKKET_ENIGHED` (Task 6).
- Produces: `PersonFakta({ visning, error }: { visning: UdgaveFaktaVisning | null; error: boolean })`.

Adfærd: én state `valgtChip` (indeks i `vaelger.chips`, nulstilles til `standard` ved ny person) styrer biografitekst og `byggUdgaveFakta(faktaInput, chip.sourceId)`. `form === 'chips'`: chips som i dag; `udgave`-chip viser »Ingen biografi fra denne udgave«. `form === 'skift'`: et lille udgaveskift over fakta uden biografitekst. »Tidligere udgave«-teksten vises, når den valgte chips udgave ikke er standardchippens. Noter under linjen: `enig` → `✓ også i <label>`; `skriver` → `<label> skriver: v1; v2`. `kunI` som afsnit sidst i fakta: `Kun i <label>` med `<Type>: <værdier>`. Børn: `fornavn · født` når `born` findes. Hovedets linjer: nøgler, der begynder med `legacy-source:`, vises ikke (spec §5.7; `lineage.ts:92` kan give dem, og `DetailPanel.tsx:121` falder ellers tilbage til `Linje <nøgle>`). Godser: kun dem, hvis `personId`'s udgave er den valgte eller null. `KildeLinjeVisning`'s klik vælger chippen med samme `recordRef`.

- [ ] **Step 1: Fejlende tests.** `PersonFakta.test.tsx`: `it('viser ✓ også i DAA 1939 under en enig linje')`, `it('viser DAA 1939 skriver: a; b')`, `it('viser Kun i DAA 1939 sidst')`. `DetailPanel.udgaver.test.tsx` (Conrad-fixture fra Task 3, bio V-1/III-58/1939): `it('åbner på V-1 og viser 2018-20's fakta')`, `it('klik på 1939 skifter biografi og fakta')`, `it('udgave-chip uden biografi viser Ingen biografi fra denne udgave')`, `it('ingen biografi og to udgaver viser udgaveskift uden biografitekst')`, `it('ingen biografi og ingen fakta viser intet vælgerområde')` (Review Focus 5), `it('barnechip viser fornavn og fødselsår')`, `it('DOM indeholder hverken record- eller legacy-source:')` — fixture med en `model.lineage.byPerson`-nøgle `legacy-source:3:II` uden navn og en record-uuid-postetiket.
- [ ] **Step 2: Kør og se dem fejle** — `npm run test -w web -- PersonFakta DetailPanel.udgaver` → FAIL.
- [ ] **Step 3: Implementér.**
- [ ] **Step 4: Udvid e2e** `person-facts.spec.ts` med en to-udgave-fixture (koordinatrækker for kilde 1 og 3, fakta for begge): forvent `✓ også i DAA 1939` synlig, klik på `DAA 1939`-chippen, og `expect(await page.content()).not.toMatch(/record-[0-9a-f]{8}-|legacy-source:/)`. Kør `npm run e2e -w web -- person-facts` → PASS.
- [ ] **Step 5: Hele node-jobbet** (Global Constraints) → PASS.
- [ ] **Step 6: Commit** — `feat(web): persondetaljen viser valgt udgave forrest og den anden som note`

### Task 8: Prod og færdigbevis

**Files:**
- Create: `docs/evidensbaseret-genimport/laeserflade-6e1-prod.md`
- Modify: `docs/changelog.md`

- [ ] **Step 1: PR** — push grenen og opret `gh pr create --draft` (push og merge kræver projektejerens ja). CI grøn.
- [ ] **Step 2: Efter projektejerens merge og Vercel-deploy: browsertjek som anon mod prod-URL'en** (spec §8, 6e-1-delen): Conrad (`/person/392`) åbner på V-1; navn, født, titel og død én gang hver; `✓ også i DAA 1939` ved født/titel/død; navnet `Conrad de Reventlow` med `DAA 1939 skriver: Conrad Reventlow`; klik på 1939 viser 1939's fakta med `DAA 1939, s. 541` og 2018-20 som note. En sammenfoldet ægtefælle uden biografi viser udgaveskift. En 1939-person uden 2018-20-modpart: ingen vælger. Ingen `record-`/`legacy-source:` i DOM'en på de tjekkede sider. Personsidens indlæsning som i dag (ingen synlig forsinkelse; biografikaldet måles i 6e-2).
- [ ] **Step 3: Skriv færdigbeviset** (kun antal, id'er og udfald; ingen tekstværdier ud over Conrads offentlige eksempel) og en changelog-linje.
- [ ] **Step 4: Commit** — `docs(6e): færdigbevis for 6e-1 i prod`

## Reviewlog

- **Codex 2026-11-12** (gpt-6.1-sol, planrunde): NO-GO, 7 fund — alle afvejet som nødvendige og små: `legacy-source:` i hovedet (Task 7), invariant »ingen oplysning forsvinder« med `kunI` som opsamling (Task 3), fritekst fra flere citationer (Task 3/6), slukket enighed giver `skriver` også for flerværdi (Task 3), godsers `(personId, id)` bevares til filtreringen (Task 6/7), `RawSource.aar` og fixture-migration (Task 6), Conrad-titelfixture med to bindinger (Task 3).
