# Tværudgave-personidentifikation ("Sammenlign udgaver") — Design

**Dato:** 2026-07-15
**Status:** Udkast — afventer PDF af anden DAA-udgave + brugergodkendelse før implementering
**Relateret:** `docs/flere-daa-udgaver-roadmap.md` (Problem 3 — dette spec; foundational for Problem 1 og 2, som
specificeres efterfølgende og refererer hertil),
`docs/superpowers/specs/2026-07-02-redaktionel-samme-som-linking-design.md` (producenten `red_samme_som`, implementeret — genbruges uændret),
`docs/superpowers/specs/2026-07-02-samme-som-collapse-design.md` (forbrugeren — kontrakten må ikke brydes),
`docs/superpowers/specs/2026-06-29-tng-qa-crosswalk-design.md` + `2026-07-01-tng-qa-relationel-corroboration-design.md` (den eksisterende matching-tilgang der genbruges).

## 1. Formål

Når en anden DAA-udgave (præsensliste eller ældre stamtavle) indlæses som ny `source` (schema.sql:32-40),
skal redaktøren kunne finde og bekræfte hvilke af den nye udgaves personer der er **samme fysiske person**
som en allerede indlæst — på trods af stavevarianter og latiniserede navneformer (Cathrina/Catharina/
Katharina, Detlev/Detlef, Sophie/Sophia, Wilhelm/Vilhelm).

Dagens værktøj skalerer ikke: `PersonPicker` (`mobile/src/components/redaktion/PersonPicker.tsx:9-41`) er en
fritekst-substring-søgning over *alle* personer uden rangering; `previewSammeSom`
(`packages/core/src/sammeSomPreflight.ts:8-18`) rådgiver først EFTER redaktøren har valgt begge personer. En
præsensliste har typisk 100-600 personer — at fritekst-søge hver enkelt mod ~1.900 stamtavle-poster er
upraktisk og fejlbehæftet (netop stavevarianterne gør at substring-søgning ikke finder kandidaten).

Featuren leverer: **(a)** en delt, deterministisk matchings-kerne der producerer en rangeret kandidatliste
pr. ny-udgave-person, **(b)** et redaktør-flow "Sammenlign udgaver" til at godkende/afvise kandidater, og
**(c)** persistens af beslutningerne — bekræftet = et helt almindeligt `samme_som`-link via den eksisterende
`red_samme_som` (schema.sql:977-1002); afvist = et nyt, minimalt `ikke_samme_som`-spor (§4). Ingen parallel
identitetsmekanisme opfindes.

## 2. Arkitektur: ren ansvarsfordeling

Samme doktrin som samme_som-spec'et §2 (Codex-3-læringen): **DB er eneste sikkerhedsgrænse for
graf-invarianter; klient-beregninger er rådgivende projektioner.** En matching-score er pr. definition
rådgivende — den beskytter ingen delte data og hører derfor IKKE hjemme i DB-laget.

| Lag | Ansvar | Håndhævelse |
|---|---|---|
| **DB-RPC/trigger** (uændret: `red_samme_som` + `enforce_samme_som_invariants`, schema.sql:944-1002; nyt: `red_ikke_samme_som`/`red_fjern_ikke_samme_som`) | Graf-invarianter (G0/G3/G4), evidens-komplet skrivning af **beslutninger** (link/afvisning), kontradiktions-guard link↔afvisning | **Autoritativ** (transaktionel, låst) |
| **Matching-kerne** (`packages/core/src/matchUdgaver.ts`, ny) | Deterministisk scoring + rangering af kandidatpar mellem to kilders personmængder; navnefoldning (§3.2) | Ren funktion, klient-side, rådgivende |
| **UI** (web `Redaktion.tsx` + mobile `redaktion/sammenlign`) | Arbejdsliste, begrundelses-visning, bekræft/afvis gennem eksisterende dry-run/LIVE-flow (`redaktionWrite`) | Rådgivende |

**Nøglebeslutning — ingen kandidat-staging:** scores er rene funktioner af data der allerede er i
redaktions-datasættet. De **genberegnes on-demand** og persisteres aldrig; kun redaktørens *beslutninger*
persisteres (samme_som / ikke_samme_som). En kandidat-tabel ville være en afledt cache der drifter så snart
redaktøren bekræfter et match eller retter en dato (samme ræsonnement som at `person.visning_*` er en
envejs-cache, schema.sql:128-134) — og den ville kræve endnu en `max(id)+1`-allokeringsflade. Arbejdslistens
tilstand er dermed *afledt*: en person er "afklaret" når alle dens kandidater ≥ review-cutoff enten er
linket eller afvist. Se §6 for hvorfor dette er en bevidst, minimal revision af YAGNI-fravalget i
samme_som-spec'et §10.

## 3. Matchings-algoritmen

### 3.1 Placering: packages/core-port af TNG-QA-modellen (ikke R-kørsel, ikke Postgres-funktion)

Tre kandidat-placeringer blev overvejet:

1. **Genbrug R-pipelinen direkte** (nyt trin i `R/tng-qa`, output til en DB-tabel). Fravalgt som *runtime*:
   outputtet er statisk og går i stå i takt med at redaktøren bekræfter matches og retter data (hver
   bekræftelse ændrer kandidatmængden — det injektive hensyn i `assign_tiers`, `R/tng-qa/04-match.R:23-51`);
   det kræver en ny kandidat-tabel + id-allokering; og R kan ikke kaldes fra redaktør-klienten. R-pipelinen
   **beholdes som kalibrerings-reference** (§3.5) — score-modellen porteres 1:1, så al indhøstet viden
   (dato-evidens-semantik, margin-gate, top-K) følger med.
2. **Postgres-funktion.** Fravalgt: `fuzzystrmatch` har ikke Jaro-Winkler, ingen af extensions
   (`pg_trgm`/`fuzzystrmatch`/`unaccent`) er i brug i skemaet i dag, og vigtigst: scoring er rådgivende, ikke
   en invariant — pr. arkitektur-doktrinen (§2) hører den ikke i DB. Redaktions-datasættet hentes alligevel
   komplet til klienten (det gør `PersonPicker` allerede via `fetchRedaktionPersoner`).
3. **TS-kerne i `packages/core`** (valgt): samme mønster som `collapseSameAs`/`sammeSomPreflight` — delt
   web+mobile, ren funktion, unit-testbar, live-genberegning. Skala er uproblematisk: selv fuld stamtavle mod
   fuld stamtavle (~2.000 × ~2.000) reduceres af blocking + `name_floor`-prune (04-match.R:138-209-mønsteret)
   til ≤ ~10⁵ scorede par — millisekunder i JS. Top-K-cap (04-match.R:193-199) porteres som sikkerhedsnet.

`matchUdgaver(kildeA: MatchFrame[], kildeB: MatchFrame[], cfg)` er en port af `build_scored` +
`assign_tiers` med samme konfigurerbare vægte (`default_cfg`, 04-match.R:3-10: navn 0.6, fødsel 0.2, død 0.1,
køn 0.1; auto_cutoff 0.90, review_cutoff 0.70, ambiguity_margin 0.05) og samme evidens-semantik:
dato-overlap tæller kun når BEGGE sider har dato (`.overlap_evidence`, 04-match.R:81-85 — ukendt dato er
manglende evidens, ikke enighed); ukendt køn giver ingen vægt (04-match.R:184). `MatchFrame` bygges af
redaktions-datasættets konkluderede fødsels-/døds-facts (`date_min/max` → årsinterval, spejler
`our_match_frame`, 04-match.R:90-113) — `redaktionRead` udvides til at eksponere år-intervaller, ikke kun
visningsstrenge.

**Populationsafgrænsning:** kandidatpar skal have **disjunkte kilder** — den nye udgaves personer matches kun
mod personer der IKKE selv er i den udgave (bogen skelner selv sine egne poster; et internt par er pr.
definition to personer). Kilde-medlemskab afledes af `person_external_id.source_id` (schema.sql:137-146),
med citation-sporet (`citation.source_id` → assertion → fact-subjekt) som fallback for kilder hvis loader
ikke skriver external-id-rækker. Krav til udgave-2-loaderen (`daa-presens`/`daa-extract`): mindst ét af de to
spor skal leveres pr. person.

### 3.2 Navnenormalisering: foldnings-nøgle = titel-strip + grafem-regler + variant-tabel

Dagens normalisering (`R/tng-qa/03-normalize.R:5-28`) fjerner kun adelspartikler/titler. Den udvides med to
lag, der producerer en **match_key udelukkende til scoring/blocking** — visningsnavne foldes ALDRIG
(diakritik-princippet fra 03-normalize.R:1 står ved magt i al visning):

**Lag 1 — deterministiske grafem-regler** (token-vis, ordnet, konservativ; hver regel er symmetrisk fordi
begge sider foldes):

| Regel | Eksempel | Note |
|---|---|---|
| `th→t`, `ph→f` | Cathrina→Catrina, Adolph→Adolf | latiniserings-klassikere |
| `c→k` foran a/o/u/l/r | Catrina→Katrina, Conrad→Konrad, Claus→Klaus | IKKE foran e/i/y (Cecilie ≠ Kecilie) |
| `w→v` | Wilhelm→Vilhelm | tysk↔dansk |
| `ck→k`; dobbeltkonsonant → enkelt | Frederick→Frederik, Detleff→Detlef | |
| `aa→å`, `ö→ø`, `ü→y` | Kaas→Kås, Jörgen→Jørgen | tysk/gammeldansk ortografi; æ/ø/å røres aldrig |
| ord-finalt `a→e` (token ≥ 4 tegn) | Sophia→Sofie*, Catharina→Katarine* | (*efter øvrige regler) |

**Lag 2 — kurateret variant-tabel** (`packages/core/src/navnevarianter.ts`, ny): ækvivalensklasser af kendte
DAA-fornavnsvarianter som reglerne ikke kan nå — `{frederik, friedrich, fritz}`, `{henrik, hinrich, heinrich,
henrich}`, `{detlev, detlef, ditlev}`, `{margrethe, margarethe, margaretha}`, `{dorothea, dorthe},
{cai, kaj, kay}` … Hvert token mappes efter lag 1 til klassens repræsentant. Tabellen er en **checked-in
TS-konstant** (versioneret, testbar, delt web+mobile) — ikke en DB-tabel (YAGNI §11; den ændres sjældent, og
eneste forbruger er matcheren). Klasser seedes fra TNG-QA's egne fund (non-anker-auto-listen i
`docs/tng-qa-koersel.md:81-83` er allerede en variantliste) og udvides empirisk under kalibrering (§3.5).

Fonetiske algoritmer (Soundex/Kölner Phonetik/Double Metaphone) blev overvejet og fravalgt: de kollapser for
groft (præcisionstab i et korpus hvor fornavne er den ENESTE diskriminator, fordi efternavnet er uniformt —
04-match.R:167-172), og de er uauditérbare over for redaktøren ("hvorfor blev disse to foreslået?"). Regler +
tabel er deterministiske, forklarlige i UI'ets begrundelse, og hver enkelt fold er unit-testbar. Genovervejes
kun hvis variant-tabellen vokser ustyrligt (§11).

**Kritisk konsekvens for blocking:** foldning skal ske **FØR** blok-nøglen dannes. Dagens blok er
førstebogstav-af-normaliseret-navn (04-match.R:103) — uden foldning ligger *Cathrina* i C-blokken og
*Katharina* i K-blokken og mødes aldrig. Blocking-skemaet i øvrigt uændret: fornavns-initial af match_key +
±5 års fødselsårsvindue (dato-løse kandidater beholdes i blokken, 04-match.R:155-164).

### 3.3 Relationel kontekst: vises, men scores ikke (v1)

04-match.R's princip "Matching ALDRIG på relationer" (linje 1) fastholdes for selve scoren; relationel
korroboration er i TNG-QA et separat efterfølgende pas (2026-07-01-spec'et). I v1 er **redaktøren**
korroboratoren: UI'et viser forældre-/ægtefællenavne side om side (§5.2) som begrundelses-kontekst uden
score-vægt. Et fremtidigt v2 kan tilføje en korroborations-bonus efter 2026-07-01-mønsteret — bevidst udskudt
til efter kalibrering mod det første rigtige udgave-par (to ukalibrerede signaler ad gangen kan ikke skilles ad).

### 3.4 Tiers: rangering, aldrig auto-skrivning

`assign_tiers`-porten beholder tre bins men **omdøber semantikken**: `auto` → **"stærk kandidat"** (score ≥
0.90 + margin ≥ 0.05 + personens topkandidat), `review` → "gennemse" (≥ 0.70), `none` skjules. Den injektive
grådige tildeling genbruges til *rangering og fremhævning* — men **intet tier udløser en skrivning**. Hvert
`samme_som`-link kræver et eksplicit redaktør-klik gennem preview-flowet (§5.3). Begrundelse: én forkert kant
karantænerer/fejlfolder en hel collapse-komponent (collapse-spec §4 — blast radius), og tærsklerne er
ukalibrerede mod DAA-mod-DAA-data (§3.5). Skalaen (hundreder af personer, ikke millioner) gør per-par-review
realistisk — modsat TNG-crosswalkens 963×kandidater.

### 3.5 Kalibrering: ærligt uafsluttet

Vægte/tærskler arves fra TNG-QA's bootstrap-kalibrering (`docs/tng-qa-koersel.md:61-92`), som selv erkender
"ikke endeligt kalibreret" og mangler et håndlabelt facit-sæt. To yderligere forbehold her: (1) foldningen
(§3.2) **flytter JW-fordelingen opad** (flere par når høj name_sim), så cutoffs kan ikke antages
overførbare; (2) DAA-mod-DAA-data har anden datokvalitet end TNG (præsenslister har ofte eksakte
fødselsdatoer — godt; ældre stamtavler har flere "ca."-intervaller — `parse_year_interval`-semantikken,
03-normalize.R:30-41, porteres). Leverance: en **kalibrerings-harness** i core (eksportér alle scorede par
som CSV + `evalPrecisionRecall` à la 04-match.R:211-215), og proceduren: efter første rigtige udgave-load
håndlabeles et facit-sæt (inkl. negative/tvetydige par), cutoffs sweepes (som `R/tng-qa/calibrate.R`), og de
valgte værdier dokumenteres i `docs/`. Indtil da er 0.90/0.70/0.05 **startværdier, ikke løfter** — spec'et
påstår ingen præcisionsgaranti.

## 4. Datakontrakt: `red_ikke_samme_som` (persisteret afvisning)

Afvisninger SKAL persisteres — ellers konvergerer arbejdslisten aldrig (afviste kandidater dukker op igen ved
hver genberegning). En afvisning er en ægte redaktionel beslutning med genealogisk værdi ("disse to er
bekræftet FORSKELLIGE personer") og lægges derfor i evidenslaget som en relation, IKKE i en ny tabel — det
giver versionering/fortryd (change_set), RLS og sletning gratis:

`red_ikke_samme_som(p_a bigint, p_b bigint)` skriver, i én transaktion (spejler `red_samme_som`,
schema.sql:977-1002, samme skabelon):

1. `relation(id, subjekt_type='person', subjekt_id=LEAST(p_a,p_b), objekt_type='person', objekt_id=GREATEST(p_a,p_b), rolle='ikke_samme_som')`
   — **normaliseret retningsløs repræsentation** (mindste id som subjekt): relationen er symmetrisk, én
   kanonisk lagring gør idempotens-/eksistens-tjek til ét opslag.
2. `assertion(id, target_type='relation', target_id=<relation.id>, vaerdi_tekst='ikke_samme_som')`
3. `conclusion(id, target_type='relation', target_id=<relation.id>, valgt_assertion_id=<assertion.id>, status='afklaret', blaastemplet_af='redaktionel identitets-afvisning')`

**Ingen `citation`** — samme begrundelse som samme_som-spec'et §3 (manuel redaktionel beslutning; provenans =
change_set + `blaastemplet_af`). **ID-allokering:** samme arvede `max(id)+1`-begrænsning som §3 dér —
accepteret, ingen ny påstand om race-frihed. Vocab-række `('rolle','ikke_samme_som')` tilføjes (mønster:
`post_load_fixup.R:54-55`).

**Guards i RPC'en** (rækkefølge efter samme_som-mønsteret: idempotens FØR change_set):
- `current_rolle() = 'redaktion'`; begge personer findes; ingen self (`p_a <> p_b`).
- Idempotens: findes `ikke_samme_som` for det normaliserede par → returnér eksisterende id, intet change_set.
- **Kontradiktions-guard:** findes et direkte `samme_som`-link mellem parret (begge retninger) → `RAISE`
  ("fjern linket først"). Spejlvendt udvides `red_samme_som` med et check der `RAISE`r hvis parret har en
  `ikke_samme_som` ("fjern afvisningen først") — at skifte mening er **to versionerede trin**, præcis som
  re-root-mønsteret (samme_som-spec §4).
- `red_relation` afviser `rolle='ikke_samme_som'` (udvid guarden schema.sql:901) — tvinger den evidens-komplette vej.

**Bevidst enforcement-grænse (ærlig, jf. Læring 3 i samme_som-spec'et):** kontradiktions-guarden ligger i
RPC'erne, IKKE i `enforce_samme_som_invariants`-triggeren. Triggeren beskytter collapse-forbrugerens delte
graf-invariant (unik sink); `ikke_samme_som` er derimod ren redaktionel workflow-tilstand som **ingen delt
forbruger læser** (collapse filtrerer på `rolle='samme_som'` — collapse-spec §4; et modstridende par degraderer
til støj i arbejdslisten, ikke datakorruption). En load-script-/rå-SQL-vej udenom guarden er derfor
acceptabel; en `db-verify.sql`-assert (intet par med både samme_som og ikke_samme_som) fanger drift maskinelt.

`red_fjern_ikke_samme_som(p_relation_id)`: valider person→person `ikke_samme_som`, eget change_set, genbrug
`_delete_relation_evidence` (schema.sql:920-929) — identisk med `red_fjern_samme_som` (schema.sql:1006-1017).

## 5. Redaktør-UI "Sammenlign udgaver"

### 5.1 Indgang og kildevalg

Ny redaktions-flade: web som sektion i `Redaktion.tsx`, mobile som route `redaktion/sammenlign` (følger
eksisterende router-konvention i `mobile/src/app/redaktion/`). Redaktøren vælger et **kildepar**: "ny udgave"
(default: `source` med højeste `aar`, schema.sql:37) mod "eksisterende base" (alle personer uden for den nye
kilde). Scoring køres on-demand i klienten (memoiseret pr. kildepar; genberegnes ved bekræft/afvis).

### 5.2 Arbejdslisten

Grupperet **pr. ny-udgave-person**, sorteret efter (tier, topscore faldende). Header viser fremdrift:
"X af Y personer afklaret · Z stærke kandidater · W til gennemsyn". Hver kandidat-række viser:

- **Score + tier-badge** (stærk/gennemse) og **felt-begrundelse som chips**: `navn 0.94` (med begge
  match_keys synlige, fx `katarine ~ katarine` — foldningen er forklarlig, §3.2), `fødsel ✓ 1912=1912` /
  `fødsel — (mangler)`, `død ✓/—`, `køn ✓/✗`. Manglende felter vises som *manglende evidens*, aldrig som match.
- **Relationel kontekst (uscoret, §3.3):** forældre- og ægtefællenavne for begge sider, side om side, med
  visuel markering ved sammenfald — redaktørens vigtigste diskriminator for ligenavngivne (Otto'erne).
- Proveniens: linje/nr (`person_external_id`) + kilde-badge for begge sider.

### 5.3 Handlinger

- **"Bekræft samme person"** → genbruger det eksisterende flow uændret: `SammeSomSheet`
  (`mobile/src/app/redaktion/person/[id].tsx:552-560`) med retningsvælger + `previewSammeSom`-hint +
  dry-run/preview → `red_samme_som` via `redaktionWrite`s eksisterende `sammeSom`-Change-art. **Ingen ny
  skrive-vej for bekræftelse.**
- **"Afvis"** → ny Change-art `ikkeSammeSom {aId, bId}` → `red_ikke_samme_som` (dry-run/LIVE som alle andre).
- **"Markér som ny person"** → afviser alle personens viste kandidater ≥ review-cutoff (bounded, typisk 1-5
  RPC-kald). Derefter er personen afklaret-som-ny pr. den afledte tilstand (§2) — intet separat
  "gennemgået"-flag persisteres. Personer helt uden kandidater listes under "formodet nye — ingen handling
  nødvendig" (transparens uden klik-pligt).
- **NN/ukendte:** personer hvis match_key er tom efter normalisering eller består af NN/N.N./ukendt-tokens
  **udelukkes fra kandidat-generering** (både som forespørgsel og kandidat) og listes separat: "kan ikke
  matches maskinelt — brug manuel søgning". `PersonPicker`-fallbacken består uændret til dette.

### 5.4 Retningskonvention (default)

Default-retning: **den eksisterende (ældst indlæste) person = kanonisk (objekt/sink), den nye udgaves person
= alias (subjekt).** Begrundelse: kanonisk id-stabilitet — sinken må ikke flytte (collapse-spec §3;
ruter/bogmærker peger på den), og den eksisterende post er den offentligt kendte. "Byt retning"-knappen
består (fjern+opret, samme_som-spec §4). For en *ældre* stamtavle indlæst senere gælder samme regel — nyeste
data vinder ikke automatisk kanonicitet; det gør den post basen allerede navigerer efter.

### 5.5 Injektivitets-advisory (rådgivende, ikke DB-håndhævet)

To FORSKELLIGE personer fra samme nye kilde må ikke begge linkes til samme eksisterende person (kilden
skelner selv sine poster). Dette kan IKKE håndhæves i triggeren: en sink har legitimt flere aliaser på tværs
af kilder (grundlægger-dubletterne III-58→V-1 mv., `post_load_fixup.R:82-83`, plus kommende
præsens-aliaser). UI'et viser derfor et advisory (mønster: pre-flight-hintet, samme_som-spec §6): *"⚠ en
anden person fra denne kilde er allerede linket til denne kanoniske"* — og arbejdslisten demoterer allerede
claimede kandidater (den injektive rangering i §3.4).

## 6. Integration med `red_samme_som` + revision af YAGNI-fravalget

Bekræftede matches ender som **helt almindelige `samme_som`-links** — trigger-invarianterne
(schema.sql:944-973), collapse-kontrakten (kun `rolle='samme_som'` + `afklaret` konklusion foldes) og
GDPR-mekanismen (completeness + RLS) er alle uændrede. Featuren er ren *producent-tilførsel*: bedre
kandidat-udvælgelse foran den eksisterende skrive-vej.

Samme_som-spec'ets §10 fravalgte "ingen 'muligvis samme som'-kladde-tilstand" og "ingen bulk/auto-matching".
Nu hvor scenariet er konkret, revideres fravalget **minimalt og asymmetrisk**:

- **"Ingen kladde-tilstand" HOLDER for positive kandidater.** Foreslåede-men-ubekræftede matches persisteres
  ikke (§2) — de er afledte, genberegnelige, og en staging-tabel ville drifte og kræve lifecycle/GC. Der
  indføres altså stadig ingen "muligvis samme som"-relation, og collapse ser aldrig noget ikke-afklaret.
- **Fravalget REVIDERES for negative beslutninger:** uden persisteret afvisning konvergerer arbejdslisten
  ikke (§4). `ikke_samme_som` er den minimale revision — én ny rolle i den eksisterende relations-/evidens-
  mekanik, to tynde RPC'er efter eksisterende skabelon, nul skemaændring.
- **"Ingen bulk/auto-matching" HOLDER.** TNG-crosswalkens auto-tier var QA-rapportering; her ville
  auto-skrivning af identitet forgifte collapse-komponenter ved fejl. Alle skrivninger er per-par,
  redaktør-bekræftede (§3.4).

## 7. `(linje, nr)`-kollisionsbuggen (roadmap-punktets del d)

`docs/reviews/24-datamodel-helhedsreview.md:145`: `post_load_fixup.R:31` vælger source som `ORDER BY id
LIMIT 1`, og `pid_of` (`:60-61`) løser `(linje, nr)` i `person_external_id` **uden source-filter**. Med 2+
DAA-udgaver kan begge dele ramme forkert udgaves person → grundlægger-`samme_som`-links og lineage-rækker mod
forkert kilde.

**Vurdering: forudsætning, ikke del af matcheren.** Buggen er implementerings-ortogonal til dette designs
kerne (den rører load-fixup, ikke scoring/UI) — men den **aktiveres af præcis den hændelse der udløser dette
design** (indlæsning af udgave 2), og reviewet kræver eksplicit at den lukkes FØR udgave 2 loades. Den
scopes derfor som **leverance 0 i denne arbejdspakke** (lille, separat commit før alt andet):

- Portér `backfill_slaegtled.R`'s fail-closed source-resolution (reviewets egen anvisning): fixup-scriptet
  tager udgave-strengen som parameter (eller resolver `udgave='DAA 2018-20'` eksplicit) og **stopper** ved
  0 eller 2+ kandidater; `pid_of(linje, nr)` → `pid_of(linje, nr, source_id)` med `AND source_id=$3`.
- Det tilstødende fund samme sted (`red_upsert_fakta`s `LIMIT 1` uden `ORDER BY`, schema.sql:581-583) er
  beslægtet men rører ikke identitets-links — ud af scope her (noteret i §11).

## 8. RLS / GDPR

- Hele fladen er **redaktion-only**: scoring kører klient-side på redaktions-datasættet, som redaktøren
  allerede henter i fuld udstrækning i dag (`fetchRedaktionPersoner`) — **ingen ny dataeksponering**. Nye
  RPC'er er `SECURITY DEFINER` + `current_rolle()='redaktion'`-gated som alle `red_*`.
- Præsensliste-personer er `levende=TRUE` — links til/mellem levende oprettes frit på evidenslaget, men
  **foldes ikke offentligt** (collapse'ns completeness-gate + RLS, samme_som-spec §8 / collapse-spec §5).
  Uændret adfærd; den offentlige folding af levende-links venter fortsat på server-side privacy-klassen.
- `ikke_samme_som`-relationer følger relations-RLS (udleveres kun når begge endpoints er offentlige). Et
  anon-synligt afvisningspar mellem to afdøde er harmløst, men offentlige read-sites skal verificeret
  ignorere ukendte roller (collapse filtrerer allerede eksplicit; `buildAux`-rolle-mapninger gennemgås) —
  test + verify-assert i §9.

## 9. Test

**Core (`packages/core/src/__tests__/`):**
- Foldningsregler enkeltvis + idempotens (fold(fold(x))=fold(x)); trioen Cathrina/Catharina/Katharina → én
  match_key; c-foran-e/i foldes IKKE (Cecilie); variant-tabel-klasser mapper til én repræsentant.
- **Blocking-symmetri:** Cathrina og Katharina lander i SAMME blok (folder-før-blok, §3.2 — regressionstest
  for den konkrete fejlmode).
- Score-paritet: fixture eksporteret fra `R/tng-qa/04-match.R` (samme input → samme scores/tiers) låser
  semantikken: `.overlap_evidence` (dato kun som gensidig evidens), ukendt køn = 0-vægt, name_floor-prune,
  top-K-rangering på fuld score, margin-gate, injektiv tildeling.
- Populationsafgrænsning: disjunkte kilder; NN/tom-nøgle udelukkes; bekræftet/afvist par forsvinder ved
  genberegning (arbejdslistens konvergens).
- Kalibrerings-harness: CSV-eksport + `evalPrecisionRecall` mod et lille håndlabelt fixture-facit.

**DB (`db-verify.sql`-asserts mod lokal prod-kopi):**
- `red_ikke_samme_som`: evidens-triple komplet; normaliseret lagring (LEAST/GREATEST); idempotens i BEGGE
  kald-retninger uden nyt change_set; self afvist; ikke-redaktion afvist.
- Kontradiktions-guards begge veje: samme_som-par → `red_ikke_samme_som` RAISEr; ikke_samme_som-par →
  `red_samme_som` RAISEr; efter `red_fjern_*` lykkes det modsatte kald (to-trins-menings-skift).
- `red_relation` med `rolle='ikke_samme_som'` afvist; `red_fjern_ikke_samme_som` + fortryd (change_set-restore).
- Verify-assert: intet personpar har både `samme_som` og `ikke_samme_som` (§4-driftfanger).
- Fixup-fix (§7): to-kilde-testdata; `pid_of` uden entydig kilde stopper fail-closed.

**App (web + mobile spejlet):**
- Change-arter `ikkeSammeSom`/`fjernIkkeSammeSom` → korrekt fn+args, dry-run vs LIVE.
- Arbejdsliste: tier-sortering, felt-chips, "markér som ny" afviser præcis de viste ≥cutoff-kandidater,
  injektivitets-advisory, retnings-default (eksisterende = kanonisk).
- Offentlige read-sites ignorerer `rolle='ikke_samme_som'` (ingen visning i publikums-UI).

## 10. YAGNI / bevidste fravalg

- **Ingen auto-skrivning af samme_som** — "stærk kandidat" er ren præsentation; hvert link er et redaktør-klik (§3.4).
- **Ingen kandidat-/staging-tabel** — scores er afledte og genberegnes; kun beslutninger persisteres (§2/§6).
- **Ingen fonetisk algoritme** — regler + kurateret tabel er deterministiske og auditérbare (§3.2); genovervej ved ustyrlig tabelvækst.
- **Ingen relationel korroboration i scoren (v1)** — vises kun; v2-kandidat efter 2026-07-01-mønsteret, efter kalibrering (§3.3).
- **Ingen DB-vedligeholdt variant-tabel** — checked-in TS-konstant; flyt til DB først hvis redaktøren skal kunne udvide uden deploy.
- **Ingen trigger-håndhævelse af link↔afvisnings-kontradiktionen** — RPC-niveau er nok; ingen delt forbruger læser `ikke_samme_som` (§4, ærlig grænse).
- **Ingen server-side batch-scoring/edge function** — klient-beregning over allerede-hentet redaktions-datasæt (§3.1).
- **Ingen ændring af offentlig søgning** (`web/src/data/browse.ts:32-33`-substring) — foldningen kunne genbruges dér, men det er et separat behov.
- **Intet persisteret "gennemgået"-flag pr. person** — arbejdsliste-tilstand er afledt af beslutninger (§5.3).
- **Ingen rettelse af `red_upsert_fakta`-nondeterminismen** (review-fund 13b) — tilstødende, men uden identitets-berøring (§7).
- **Ingen ny GDPR-mekanik** — levende-links folder fortsat ikke offentligt; server-side privacy-klasse er stadig separat fremtidigt arbejde (§8).

## 11. Berørte filer (forventet)

- `schema.sql` + `db-migrations.sql` — `red_ikke_samme_som` + `red_fjern_ikke_samme_som`; kontradiktions-check
  tilføjet i `red_samme_som`; `red_relation`-guard udvidet (schema.sql:901); vocab-række. Alt idempotent.
- `db-verify.sql` — asserts (§9), inkl. kontradiktions-driftfangeren.
- `packages/core/src/matchUdgaver.ts` (ny) + `packages/core/src/navnevarianter.ts` (ny) + `index.ts`-eksport.
- `packages/core/src/__tests__/` — foldning/blocking/score-paritet/konvergens + kalibrerings-harness.
- `web/src/data/redaktionWrite.ts` + `mobile/src/data/redaktionWrite.ts` — Change-arter `ikkeSammeSom`/`fjernIkkeSammeSom`.
- `web/src/data/redaktionRead.ts` + `mobile/src/data/redaktionRead.ts` — kildeliste, år-intervaller (§3.1),
  eksisterende `ikke_samme_som`-par, kilde-medlemskab (`person_external_id`/citation-spor).
- `web/src/Redaktion.tsx` (ny sektion) + `mobile/src/app/redaktion/sammenlign.tsx` (ny route) — arbejdslisten (§5).
- `.claude/skills/daa-extract/scripts/post_load_fixup.R` — leverance 0: fail-closed source-resolution (§7).
- Tests: `web/src/data/__tests__/`, `mobile/src/data/__tests__/`.
- Efter godkendelse: notat i `docs/decisions.md` + status-opdatering i `docs/flere-daa-udgaver-roadmap.md`.
