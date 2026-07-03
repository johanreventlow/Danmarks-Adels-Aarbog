# Changelog

## Børn af flergifte forældre knyttet til korrekt union (2026-07-03)

Loaderen hang tidligere ALLE børn af en flergift forælder på forælderens FØRSTE union
(`load_daa.R`, `fam <- fams[[1]]`), så børn af 2./3./4. ægteskab blev fejl-tilknyttet 1.
ægteskab. Generelt problem: 20 flergifte forældre, 65 børn berørt — fx alle Conrad de
Reventlows 10 andet-ægteskabs-børn (inkl. dronning Anna Sophie) lå på Anna Margaretha Gabel
i stedet for Sophia Amalia Hahn. Dataene til at rette det lå der hele tiden i hvert barns
`aegteskab_kontekst`.

**Loader (`load_helpers.R` + `load_daa.R`):** delt DB-fri matcher `match_barn_union()` — barnets
`aegteskab_kontekst` → rette union; partnernavn primær anker, ordenstal kryds-tjek, NA ved
uenighed/ukendt partner (gætter aldrig). Wired i child-loop via `recmap` (nøgle→rec); kun ved
2+ ægteskaber; uafklarede parkeres på partnerløs union frem for fejl-link. 34 testthat-tests.
Eksekveret write-frit mod alle 591 records via `--dry-run` (parkerede præcis 1: III-85).

**Prod-data (`fix_boern_multi_union.R`, samme matcher):** 64 børn flyttet, 1 parkeret, i ét
`change_set` (id 1, fortrydbart via `red_fortryd_change_set(1)`); idempotens-guard. Verificeret:
Conrad Gabel 6 / Hahn 10; 132 change-events (64×2+2+2 → intet barn tabt); kun family/family_member
berørt; acceptance-gate grøn (Anna Sophie nu på Hahn).

**Udestår:** III-85 (Detlef) har nu kun far — falsk Brockdorff-mor fjernet, men hans
`aegteskab_kontekst` beskriver hans EGET ægteskab, så moderen er uoprettelig fra feltet; på
partnerløs park-union, flagget til manuel genealogisk review.

## Redaktør-web-cohesion: v2-header + person-browse (2026-07-03)

Bragte redaktør-fladen (`web/`) i tråd med publikums-web-v2 (Følgesvend). Committet `91b7797` på
`feat/samme-som-collapse`; header-ændringerne ført både i design-mockuppen og den kørende app.

**Header (`design/project/Reventlow-redaktion.dc.html` + `web/src/Redaktion.tsx`):** DAF-logo-lockup +
"Danmarks Adels Aarbog" + mono "Redaktion · Dansk Adels Forening" (erstatter R-firkant + "Redaktion ·
Reventlow"); slægt-chip m. crest-ring + "Reventlow ▾" (verbatim fra web-v2); header-mål 66px/gap 22/
padding 0 26px; mockup-link "Åbn publikumsvisning" → web-v2 (v1→v2).

**Person-liste (spejler Følgesvend §9.1/§9.2):** A–Å grupperet liste + alfabet-hop, sortér navn/fødeår
(`RedPerson.born`, aldrig dødsår), linje-filter som chips fra `model.lineage` (filtrerer KUN listen —
redaktør har intet stamtræ at hoppe fokus i). `buildBrowse` generaliseret strukturelt (`BrowsePerson`)
så samme testede motor driver både `ModelPerson` og `RedPerson` via et `name`-alias; id-rummene flugter
fordi redaktør-modellen loades `collapse:false`. Ikke-person-entiteter beholder den flade søgeliste.

**/simplify (4 parallelle agenter):** `personBrowse` gated til person-entiteten (ellers null — sparer en
900+-personers browse ved hvert tastetryk under andre entiteter); to næsten-ens række-renderere gen-forenet
til én `listRow`-helper; `browseInput`-memo inlinet; memo-dep smalnet til `lineage.byPerson`. Udskudt (uden
for diff): udtræk delt `LinjeChip`/`<BrowseControls>` på tværs af Følgesvend+Redaktion.

**Verifikation:** `tsc` rent · 94/94 web-tests (18 browse) · prod-build OK. **Ikke** visuelt/runtime-verificeret
i browser (ingen browser-driver i repo'et).

## Redaktionel samme_som-linking implementeret + DB live i prod (2026-07-02)

Redaktør-funktion til at markere to `person`-poster som samme fysiske person (producenten til det
allerede-live collapse). Fuld cyklus: brainstorm → 3× Codex-review (design+spec) → 7-task TDD-impl → /simplify.

**DB (LIVE i prod, ende-til-ende-verificeret):** `enforce_samme_som_invariants`-**trigger** (BEFORE INSERT
på `relation`) håndhæver graf-invarianterne (self-link, unik sink/ingen multi-sink, ingen re-root) for ALLE
insert-veje — ikke kun RPC'en (Codex-3-fund: en RPC-lokal check kan omgås af `red_relation`/undo/load/manuel).
`red_samme_som` (evidens-komplet wrapper: relation+assertion+afklaret-conclusion, advisory-lås, idempotent) +
`red_fjern_samme_som` (komplet evidens-slet via delt `_delete_relation_evidence`-helper) + `red_relation`
afviser `rolle='samme_som'`. Anvendt via MCP `apply_migration`; verificeret mod prod med rollback-DO-blok
(opret/idempotens/G3-multi-sink/self-link/fjern) — 0 muterede rækker, 2 rigtige links intakte.

**App (web+mobile spejlet, testet):** `sammeSom`/`fjernSammeSom` Change-arter, `fetchSammeSomLinks` +
retnings-mapping, rådgivende `previewSammeSom` (kører collapse med hypotetisk kant), og UI i person-editorens
relations-sektion ("Samme person"-liste + fjern + "Marker som samme person" → PersonPicker → retningsvælger +
pre-flight-hint → dry-run/LIVE). Mobile 247, web 94, tsc rent.

**Codex-fund (3 runder, alle løst):** invariant → trigger (H1); enten-retning skjuler re-root → modsat-retning
afvist, re-root=fjern+opret (H2); slette-orden fejler på citations → genbrug komplet sekvens (H3); pre-flight
ikke-autoritativt (RLS-datasæt-afvigelse); evidens-kontrakt (valgt_assertion_id/blaastemplet_af); concurrency
→ advisory-lås; `max(id)+1`-race = arvet codebase-begrænsning (bruger-accepteret v1). /simplify: delt
delete-helper + fjernet død G5-trigger-walk. Spec: `docs/superpowers/specs/2026-07-02-redaktionel-samme-som-linking-design.md`.

**Udestår:** manuel live-verifikation af UI'et (web-browser + Expo).

## samme_som-collapse implementeret (web + mobile) (2026-07-02)

Frontend identitets-projektion: en person der optræder som flere DB-poster (linket via
afklarede `samme_som`-relationer) vises nu som ÉN person i søgning, person-visning og
slægtskabsfinder — i **både web og mobile**. 9-task plan (`docs/superpowers/plans/`)
implementeret TDD, dual-reviewet efter hvert logisk trin.

**Kerne (`collapseSameAs.ts`, spejlet web+mobile):** ren funktion der grupperer `samme_som`-
linkede id'er (union-find), vælger kanonisk = unik sink, **validerer og karantænerer** konflikter
(self-forælder/-ægtefælle, global cyklus, konkurrerende forældre, hard vital/køn-konflikt) på den
kombinerede projicerede graf via en **fixed-point-løkke**, fletter person-posterne (coalesce,
`years`-regen, `privat=OR`, konfidens-stærkeste kant-dedup) og omskriver alle graf-kanter til
kanoniske id'er FØR `buildModel`. Motoren (`buildModel`/`relationship`) er URØRT. Reversibel:
returnerer `canonicalIdById` + `mergedFrom` + `quarantined`.

**Integration:** `load.ts`/`model.ts` henter godkendte `samme_som` (relation + afklaret conclusion,
polymorf → to fetches + JS-match) og folder før `buildModel`. Alle person-id-bærende Aux-strukturer
kanoniseres; `linjeByPerson` er nu multi-linje. Rute/fokus/rel/mig-id'er resolves gennem alias-map
(inkl. `meId` ved read-site). Person-visningen viser multi-linje badge + proveniens-note
("Optræder i Aarbogen som …"). Redaktion collapser IKKE (ser separate DB-poster).

**Dual-review (7 kerne-fund + 3 integrations-fund, alle rettet):** Codex opgraderede to "defer"
til reelle silent-corruption-bugs (konkurrerende forældre maskeret af rejekteret gruppe →
fixed-point; konfidens-nedgradering ved dedup). code-analyzer fangede et meId-read-site-bug
(★ Dig-badge brød for foldede personer). Se `docs/reviews/16-samme-som-collapse-kerne.md`.

**Empirisk valideret mod prod:** de 2 eksisterende `samme_som` (Conrad III-58→V-1, Detlef
III-104→IV-1) er begge `afklaret`, cross-linje, konflikt-fri → folder rent; founder'en arver
sit forælder-link (der før manglede på founder-posten). Suiter: mobile 236, web 84.

**Udestår (manuel):** Expo-simulator + web-browser-verifikation af selve skærmene (navigation
via begge alias-ruter → samme samlede person + badge).

## DAA-reimport Etape 1+2, data-tab-genopretning, grundlægger-links, samme_som-design (2026-07-02)

**Etape 1 — loader/validate-hærdning (merget til main, pushet):** 9-task subagent-drevet
forløb (final-reviewet af Opus). Partner-dedup via `partner_ekstern_ref` (dry-run: 41 færre
dubletter); børne-løkke rewrite (15a/15b-opslag + observerbar logging af uopløste — kun 3
uopløste i hele stamtavlen); deterministisk `date_min/max` fra `date_raw` (+ floruit-spans);
`--dry-run` + RESET-guard (fail-closed) + `--force-reset`; frossen trin ③-prompt
(`references/extract-prompt.md`). Union-heuristik reverteret efter Opus-review (brugte
forkert kontekst-entitet, 0-impact). Suiter: R 181, validate 38, escalate 16.

**Data-tab-hændelse + Etape 2-reload:** Live-basen (`xjnvdhajfyrcytatnzos` — appen, R og MCP
peger alle her) var i en TIDLIGERE session overskrevet til 3 test-personer. Bruger godkendte
reset-reload af fuldt datasæt: `load_daa.R clean-v2.json --reset --force-reset` → **922
personer** (41 færre dubletter), cache regenereret, 70 levende. TRUNCATE CASCADE ramte også
`profiles`/`lineage`/`suggestion` → genoprettet (redaktør-profil for johan@reventlow.dk;
5 lineage-navne) i et durabelt, idempotent `post_load_fixup.R` (par-opslag på linje/nr =
reload-sikkert). Ryddet 32 orphaned `change_set` + 191 `change_event`.

**TNG-QA-måling (docs/reviews/tng-qa-rapport-2026-07-02.md):** manglende relations-links
**125 → 10** (Etape 1 genindvandt 92%), enig 177 → 288, 0 falske links. Bekræfter empirisk
at de manglende links var et linking-problem (bucket c=0), ikke et udtræks-problem — re-udtræk
var ikke nødvendigt. Rest: 10 kryds-linje-links (Etape 4) + 5 dato-uenigheder (fejl-attribueret
`date_raw`).

**Grundlægger-identitets-links:** Conrad de Reventlow (III-58↔V-1) + Detlef de Reventlou
(III-104↔IV-1) — samme person i to linjer — linket via `samme_som`-relation (evidenslag),
bekræftet via TNG-crosswalk. Løser samtidig 2 af de 10 manglende links.

**samme_som-collapse — design + plan (dual-reviewet, ikke implementeret):** frontend
identitets-projektion så en person med flere DB-poster vises som ÉN (søgning/person-visning/
slægtskabsfinder). Spec `docs/superpowers/specs/2026-07-02-samme-som-collapse-design.md`
(Codex-reviewet: valideret reversibel projektion, completeness-baseret GDPR, konflikt-karantæne).
Plan `docs/superpowers/plans/2026-07-02-samme-som-collapse.md` (9 tasks, web+mobile). **Klar til
implementering næste session.**

## Flere-forældrepar datafix (2026-07-01)
* **Bruger observerede** at personer så ud til at have flere forældrepar. Undersøgt:
  90 personer med beviseligt modstridende forældrepar, 163 fejlagtige `barn`-links i alt
  (af 559). Rodårsag: `load_daa.R`'s child-linje-fallback prøvede et upålideligt LLM-udtrukket
  `boern.linje`-felt FØR forælderens egen linje — når feltet var forurenet, matchede et
  genbrugt løbenummer nogle gange en helt anden gren/generation.
* **Rettet:** `load_daa.R:246-260` dropper nu `stated`-fallback helt, matcher
  udelukkende egen linje (så en gen-indlæsning ikke kan genskabe fejlen). Prod-data
  korrigeret ved SQL-sletning af de 163 spuriøse rækker (kørt som versioneret `change_set`
  #3, fuldt fortrydbart), lokal backup af `family_member` gemt i `work/`. 4 personer uden
  linje-match + 46 nu-forældreløse personer er sandsynligvis rescuable via en målrettet
  gen-kørsel af den fixede loader (ikke gjort her — kræver egen plan). Sideeffekt: løste
  også den tidligere kendte era-tie-break-fejl (børn født før forældre) fuldt ud.
  Se `docs/reviews/11-flere-foraeldre-datafix.md`.

## Versionering + hyperlinks — real-device Expo-verifikation + DB-bugfix (2026-07-01)
* **App-lag afprøvet på ægte iPhone-simulator mod rigtig prod-Supabase** (`idb`-baserede taps,
  ikke kun statisk `tsc`/jest). Konfirmeret empirisk: hyperlink-rendering/navigation,
  bio-klamp, MentionPicker insert-at-cursor, fortryd-flow, redo-knap på reversal-post.
  Konflikt-retry (B9-divergens) forbliver utestet.
* **DB-bug fundet + rettet:** `_version_upsert_row` (fortryd-restore-helper) manglede eksklusion
  af `GENERATED ALWAYS`-kolonner fra sin dynamiske `INSERT`/`ON CONFLICT`-kolonneliste —
  Postgres tillader slet ikke en eksplicit værdi for disse. Ramte `narrative.fts` (aktiv
  fuldtekstsøgning i prod, selvom CLAUDE.md §9 hævdede den var kommenteret ud — schema-drift).
  Konsekvens: fortryd fejlede hårdt for ENHVER tabel med en generated-kolonne. Transaktionen
  rullede korrekt atomisk tilbage (ingen delvis korruption), fundet + rettet + genverificeret
  ved en ægte LIVE-testskrivning + fortryd på en obskur testperson (godkendt af bruger).
  Migration anvendt til prod; `schema.sql`/`db-migrations.sql` opdateret.
* **UI-bug fundet + rettet (brugerfund):** dry-run-toggle-switchen i `redaktion/person/[id].tsx`
  havde omvendt polaritet ift. den identiske switch på Konto-/dashboard-skærmen — samme felt,
  modsat "til højre = sikker"-betydning afhængig af skærm.
* Se `docs/reviews/10-app-lag-hyperlinks.md` for fuld verifikations-log.

## Versionering + hyperlinks (App-lag, RN/Expo) — kode-komplet, dual-reviewet, IKKE Expo-kørt (2026-06-30)
* **Hyperlink-tokens i narrativ:** `mentions.ts` (parser/encoder, ren funktion, 17 jest-tests)
  + `NarrativRenderer` (klikbar visning, wrapper `Typography.Body` 1:1) + `MentionPicker`
  (@-mention-søgning, indsæt-ved-cursor i redaktør-editoren).
  Token-grammatik (spec §5.1): `[[type:id|tekst]]`, 10 fast entity-typer, `\|[]`-escape.
* **Redaktionel historik-skærm** (`redaktion/historik/[id].tsx`): change_set-liste m. "Fortryd"
  + en samlet døde-links-rapport (D1/D3). Fortryd ruter gennem den eksisterende
  `pending`+`SkrivePreviewSheet`-modal (dry-run/LIVE-bekræftelse) — IKKE et direkte
  `submitChange`-kald, som var en tavs no-op i dry-run (fanget proaktivt før review).
* **Dual-review (cycle 10, Claude+Codex):** H1 [HIGH] escape-asymmetri — `makeToken` eskaperede
  ikke `\` selv, så et label der ender på backslash fik scanneren til at sluge afgrænserens `]`
  og hele tokenet lækkede som synlig tekst. Min første fix-recipe (narrow scanner-regex) var
  selv FORKERT — Codex korrigerede til encode-siden (escape `\` i `makeToken`); empirisk
  verificeret med 7 round-trip-cases. H2 [MEDIUM] `reverteret`-feltet havde omvendt semantik
  (`reverterer_id` peger FRA den nye fortrydelse TIL den originale, ikke omvendt) — Fortryd-
  knappen forblev aktiv på allerede-fortrudte poster. M3 [MEDIUM, Codex-only fund] stille
  fejl-svælgning i `MentionPicker` umuliggjorde at skelne netværksfejl fra reelt nul personer.
  Se `docs/reviews/10-app-lag-hyperlinks.md`.
* **`/simplify`:** 6 behavior-preserving cleanups (NarrativRenderer→Body-wrapper, dødt
  TYPES-sæt + dead defensiveness i mentions.ts, `erFortrydKonflikt`-ekstraktion + regressionstest,
  unødig Number/String-tur-retur fjernet, `useRef` i stedet for `useState` til cursor-position).
* **Verifikation: `tsc --noEmit` 0 fejl, jest 197/197 grøn.** Det er taget for hvad det er — det
  dækker rene funktioner og mappere, IKKE render/interaktion (cursor-indsætning i `TextInput`,
  nested-`Text`-clamp, `Alert`-flow). **Ikke Expo-kørt i denne session** (intet device/simulator
  tilgængeligt) — se manuel punch-list i review-dokumentet, §"Manuel Expo-verifikation".
  Vigtigst deri: eksisterende narrativer i basen har INGEN `[[...]]`-tokens endnu (funktionen
  er ny), så `NarrativRenderer` over LIVE-data i dag tester reelt kun plain-text-fallbacken.
* **Branch `feat/versionering-hyperlinks-app-lag` ikke merget/pushet** — afventer brugerens
  beslutning (git-gate).

## Versionering + hyperlinks (DB-lag) — implementeret, dual-reviewet, applied til prod (2026-06-30)
* **Fortryd-bar redaktionel ændringshistorik:** hybrid change-set-log (`change_set`/
  `change_event`) — hver `red_*`-skrive-RPC åbner et re-entrant `change_set`, og en generisk
  `log_change`-trigger på alle 22 versionerede tabeller snapshotter før/efter-tilstand
  (kolonne-projektion: `visning_*`/`email`/`rolle` ekskluderet). `red_fortryd_change_set`
  inverse-applier ét sæt i én transaktion med optimistisk divergens-tjek.
* **Append-baseret `red_edit_oplysning`:** ny påstand + re-peg konklusion (ærer invariant #1);
  returtype `void→jsonb` (`ny_assertion_id`). App-laget upåvirket (consumer læser ikke retur).
* **Hyperlinks i fri-tekst:** `[[type:id|tekst]]`-tokens → `parse_mentions` + afledt
  `text_mention`-indeks (regen-trigger på narrative/note) + døde-links-view. RLS dobbelt-gating.
* **Historik-API:** `hist_for_subjekt`/`hist_events` (redaktion-only, SECURITY DEFINER);
  deny-all RLS på historik-tabeller.
* **TDD mod lokal prod-kopi** (free tier → ingen branch; postgresql@17 + auth-shim + read-only
  pg_dump). **5 bugs fanget før prod:** 3 under impl (begin_change_set-placering ved flerlinjet
  rolle-tjek, assert-filter-fejlklassificering, `FOREACH IN ARRAY NULL`-crash) + 2 HIGH i
  dual-review (Claude+Codex+code-analyzer, konvergent): DELETE-inverse manglede divergens-tjek
  (blind PK-overskrivning) og `_version_upsert_row` nulstillede NOT NULL skip_cols
  (`profiles.rolle`-crash). Begge empirisk reproduceret + regressions-testet. Se
  `docs/reviews/09-versionering-hyperlinks-db.md`.
* **Applied til prod Supabase (atomisk, --single-transaction):** verificeret — 4 tabeller,
  22 log-triggere, RLS aktiv, `red_edit_oplysning`→jsonb, 963 personer uændret. Pre-apply
  schema+data-backup taget lokalt. 24 verify-asserts grønne + clean-slate-konsistent.
* **Bevidst deferret:** TOCTOU (single-writer PoC), parse_mentions open-token (delt-parser/app-lag),
  `red_doede_links` dækker 3/10 mention-typer (completeness).

## TNG-QA: pipeline komplet ende-til-ende (Trin 1-6) + kalibrering (2026-06-30)
* **Forbindelses-bug fixet:** top-level `on.exit()` under `source()` fyrede
  `dbDisconnect(shutdown=TRUE)` FØR næste query → "Invalid connection". Lukker nu
  forbindelser efter sidste brug.
* **Trin 3-4-glue (`scored` → `crosswalk`):** `our_match_frame`/`tng_match_frame`/
  `build_scored` — blokering på fornavns-initial + fødselsår-vindue, vektoriseret
  overlap, top-K pr. person rangeret på score. Fix: `person.id` bigint→integer
  (data.frame recycler ikke integer64); DATE→år-konvertering.
* **Auto-tier bootstrap-kalibreret:** den uniforme "Reventlow" gjorde `unique_block`
  ubrugelig (auto=0). Erstattet med ambiguitets-margin (`ambiguity_margin=0.05`):
  auto kræver score≥0.90 OG bedste kandidat klart foran nr. 2 OG top-kandidat.
  Kalibreret mod bootstrap-ankre (entydige eksakte matches). `calibrate.R` ny.
* **Dato-overlap som scoring-evidens:** `birth/death_overlap` er nu kun TRUE ved
  reel dato på begge sider (`.overlap_evidence`) — fjerner 0.3 "gratis" vægt på
  dato-løse par. Auto kræver nu reel fødselsårs-korroboration. auto≈347, review≈658.
* **Trin 5 gen-kørsels-crash fixet:** review-køen skrives nu med udfyldelig
  `afgoerelse`-kolonne; `merge_review_decisions` tåler tom/manglende afgørelse.
* **Trin 6 aktiveret — relations-QA mod TNG:** sammenligner ægteskaber/forælder-barn/
  datoer/køn; producerer `docs/reviews/tng-qa-rapport-<dato>.md`. **GDPR PII-gate =
  input-gating** (filtrér begge sider til afdøde-ikke-private FØR sammenligning,
  fail-closed) — verificeret 0/70 levende-id i rapporten. Første kørsel: 183
  handlingsorienterede uenigheder.
* **Tests:** 35 (match/report/review/extract/pull), alle grønne.

## Slægtskabsfinder: bilineal multi-linje + konfidens på stien (2026-06-30)
* **Bilineal:** "Er vi i familie?" (`mobile/src/data/relationship.ts`) traverserer nu BEGGE
  forældre-linjer (BFS over `parentsByChild`) i stedet for kun den primære forælder-kæde.
  Slægtskab via mor-linjen blev før tavst overset — en reel korrekthedsfejl i en sammengift slægt.
* **Multi-linje:** returnerer alle distinkte forbindelses-linjer (`lines[]`), nærmeste først.
  Anepar grupperes til ÉN linje (helsøskende vises ikke som to). Klassisk dobbelt-fætterskab
  giver to anepar-linjer. "Halv" markeres kun når den anden forælder faktisk er kendt og
  forskellig (ingen falske halvsøskende fra datahuller).
* **Køn:** kønsbestemte moderne etiketter (Fætter/Kusine, Onkel & niece, Mor & søn) via
  `person.koen`, med kønsneutral fallback der matcher de oprindelige strenge.
* **Konfidens på stien (invariant #7):** `family_member.konfidens` trækkes nu ind i modellen
  (loader + kant-indeks `konfByEdge`). Hver linje beregner sit SVAGESTE staterede led; en sti
  gennem et formodet/omstridt led flages (`usikker`) — på resultat-kortet, pr. trin på
  tidslinjen, og på øvrige linjer. Uangivne led larmer ikke. Samme kant med flere påstande
  beholder den stærkeste konfidens. *Hage:* de fleste eksisterende links er `NULL` (bulk-load),
  så visningen viser usikkerhed i takt med at konfidens-data berigt (fx de 97 kendte fejl-links).
* **Datalag:** `koen` + `konfidens` tilføjet til visningsmodellen (types + loader), bagudkompatibelt.
* **Tests:** relationship-suiten udvidet 6 → 27 (bilineal, anepar-collapse, halv, dobbelt
  fætterskab, kønsetiketter, konfidens-svageste-led). Hele suiten 141/141 grøn, tsc + eslint rene.
* **Roadmap:** `docs/moed-en-slaegtning-roadmap.md` — telefon-til-telefon slægtskab ved fysisk
  møde (NameDrop-stil dobbelt-aktiv-handling, QR-MVP → BLE → UWB, GDPR-samtykke-design).

## Opret-ny-entitet — Tilføj-fanen (2026-06-29)
* **Hvad:** Redaktøren kan oprette ny person/gods/kilde/organisation fra "Tilføj"-fanen gennem
  dry-run→live-gate; person → lander i editoren, øvrige → vises i listen.
* **4 nye SECURITY DEFINER RPC'er (deployet prod):** `red_opret_person` (INSERT + navn/født/død/titel
  som facts via `red_upsert_fakta`, privat=true default), `red_opret_estate`, `red_opret_kilde`,
  `red_opret_organisation`. id=max+1, NULL/whitespace-navn afvist. Grants tilføjet i
  `db-migrations.sql` (schema.sql bærer ingen grants by design; db-rls.sql grant-loop dækker red_*).
* **B1/B2 (Codex-review):** `loadRedaktionModel(force)` tvinger reload (var no-op på 'ready');
  `SkrivePreviewSheet.onApplied(result)` bærer ny id til navigation.
* **`OpretSheet`:** grid + per-type formularer; `buildRpcCall`-cases for 4 opret-arter; enkelt-Modal
  (kun én Modal synlig ad gangen via `visible={visible && !pending}`); wire til Tilføj-fanen.
* **Privatliv:** ny person privat=true (levende=false=anon-læsbar → glemt toggle ville publicere).
* **Udskudt:** sted-picker til gods (ingen place-picker/placeListe); inline-opret fra PersonPicker;
  medie/våben/majorat; dedup-UNIQUE; id-sequence (post-PoC).
* **Test:** jest (`buildRpcCall` opret-arter) + DB rollback-test + manuel web-e2e.
* **Codex-review-fix (2026-06-30):** nestet native Modal fjernet — OpretSheet rendrer nu én Modal
  ad gangen + SkrivePreviewSheet som søskende; Task 1 happy-path-test omskrevet fra psql-`\gset`
  til `DO`-blok med `RAISE EXCEPTION`-asserts (eksekverbar via `execute_sql`).
* **GDPR-hærdning cycle-08 (2026-06-30):** `p_privat`-param fjernet fra `red_opret_person` — privat
  er nu FORCERET `true` i INSERT-kroppen; gammel 7-arg-signatur DROPpet på PROD (ny 6-arg erstatter).
  Synlighed skiftes herefter udelukkende via `red_set_privat`. `OpretSheet` og `buildRpcCall`
  fjerner `privat`-feltet fra payload; jest-test opdateret (30/30). Lukker anon-eksponerings-footgun:
  en crafted RPC-kald med `p_privat=false` kunne gøre en afdød person anon-læsbar ved opret.

## Plan 2C-2b — redigerbar familie-sektion (partner + barn + konfidens) i redaktør-person-editoren (2026-06-29)
* **Hvad:** Redaktøren kan nu tilføje og afkoble ægtefælle/partner, tilføje og afkoble børn
  samt justere konfidens på familie-links direkte i person-editoren — alt via det eksisterende
  SkrivePreviewSheet-gate (dry-run → live). HVERV/GODSER/KILDER er uændrede fra 2C-2a.
* **4 nye SECURITY DEFINER RPC'er (deployet mod prod 2026-06-29):**
  - `red_opret_union(p_partner_a, p_partner_b, p_type, p_ordinal)` — opretter ny family-entitet
    + 2 partner-links. INGEN auto-dedup: samme par kan gifte sig igen — par-dedup ville flette
    børn og event-tidslinjer fra to selvstændige ægteskaber (Codex H2). partner_a==b og ugyldig
    type afvises med RAISE.
  - `red_tilfoej_barn(p_family_id, p_barn_id, p_rolle, p_konfidens)` — tilføjer barn-link til
    eksisterende family. Cyklus-guard via recursiv CTE: tilføjer en ane som barn → RAISE (Codex H3).
    Selv-forælder (barn==en af familiens partnere) afvises. PK-dublet = no-op. Ugyldig
    rolle/konfidens afvises.
  - `red_set_familie_konfidens(p_family_id, p_person_id, p_rolle, p_konfidens)` — UPDATE
    `family_member.konfidens` for præcist ét link; ukendt link → RAISE; ugyldig konfidens → RAISE.
  - `red_slet_familie_link(p_family_id, p_person_id, p_rolle)` — sletter KUN `family_member`-rækken.
    Sletter ALDRIG `family`-entiteten (heller ikke når det er det sidste link), da family bærer
    276+ facts og 700+ notes uden FK — en family-sletning ville efterlade al evidens forældreløs
    (Codex H1).
* **`fetchPersonFamilie`** — per-person familie-fetch (unioner + barn-af-links), separat fra
  `redaktionAux` der ikke eksponerer `family_member.konfidens` eller de primærnøgler
  (`family_id`/`person_id`) som slet- og konfidens-kaldene kræver.
* **`eraAdvarsel`** — klient-side blød dato-advarsel (barn født udenfor forældrenes plausible
  livsrum). Advarer og tillader — afviser ikke. 27 verificerede historisk-inkonsistente tilfælde
  i eksisterende data ville trigger en hard-reject uberettiget.
* **`PersonPicker`** — sheet-komponent til valg af person (søg + tryk), brugt ved
  "+ Tilføj partner" og "+ Tilføj barn" i editoren.
* **`buildRpcCall`-cases** for `opretUnion` / `tilfoejBarn` / `setFamilieKonfidens` /
  `sletFamilieLink`; type `Change` udvidet med `familyId`, `personId` (familie-kontekst)
  og de 4 nye Change-arter.
* **Redigerbar ÆGTEFÆLLE/BØRN/FORÆLDRE-sektion** i person-editoren: tilføj partner
  (PersonPicker → opretUnion), tilføj barn (PersonPicker → tilfoejBarn, m. era-advarsel),
  juster konfidens (KonfidensVaelger → setFamilieKonfidens), afkobl
  (sletFamilieLink). FORÆLDRE-sektionen (personen som barn): forældre-NAVNE er read-only, men
  konfidens kan justeres og forkert forælder kan afkobles ("🗑 afkobl forælder" → sletFamilieLink).
* **Test:** 121/121 jest, tsc rent.
* **Controller-gate kørt (2026-06-29):** schema-backup (15 funktioner →
  `docs/db-backups/2026-06-29-prod-red-functions-2c2b-pre.sql`), 4 RPC'er deployet + grant-loop re-kørt,
  rollback-tests bestået (nul mutation): H2 samme par → 2 selvstændige unioner (ingen kollaps); H3
  cyklus-guard + selv-forælder afvist + PK-dublet no-op; konfidens-UPDATE + valideringer; H1 slet alle
  family-links → family-entitet + 276+ facts + 700+ notes INTAKT.
* **Final-review-fix:** era-advarsel medtager nu fokus-forælderens egne datoer (manglede → eget barn-tilføj
  ikke era-tjekket, dødt for én-forælder-unioner).
* **Udestår:** kun manuel web-e2e. Bredere redaktionModel-invalidering efter familie-write = §9-follow-up.


## Plan 2C-2a — redigerbar sektion-relationer (hverv/godser) i redaktør-person-editoren (2026-06-29)
* **Hvad:** Redaktøren kan nu tilføje og slette hverv- og godser-relationer direkte i person-editoren.
  Familie (family_member) og kilder (external_id) forbliver read-only i denne plan; familie-redigering
  er udskudt til 2C-2b. Alle ændringer passerer igennem det eksisterende SkrivePreviewSheet-gate
  (dry-run → live).
* **To nye SECURITY DEFINER RPC'er (deployet mod prod 2026-06-29):**
  - `red_slet_relation(p_relation_id)` — FK-ordnet evidens-cascade:
    citation → conclusion → assertion → note → relation. Nødvendigt fordi relations bærer ~955
    evidens-rækker uden FK (target_type/target_id er polymorft, ingen cascade-constraint).
  - `red_tilfoej_relation(p_subjekt_id, p_objekt_type, p_objekt_id, p_rolle, p_periode_raw)` —
    validerer objekt_type + eksistens, dup-guard (returnerer eksisterende id ved gentagelse,
    ingen dublet), indsætter relation.
* **`fetchPersonRelationer`** — ny pagineret per-person relations-fetch (ikke via `redaktionAux`,
  som dropper relation-id'er og ikke kan bruges til slet-kald).
* **`EntitetPicker`** — sheet-komponent til valg af entitet (gods, organisation m.fl.) med
  type-menu + navne-liste, brugt ved "+ Tilføj hverv/gods" i editoren.
* **`buildRpcCall`-cases** for `sletRelation` + `tilfoejRelation` (relations-kald vha. eksisterende
  write-gate); type `Change` udvidet med `relationId`, `sletRelation`, `tilfoejRelation`.
* **Test:** 109/109 jest, tsc rent.
* **Controller-gate kørt (2026-06-29):** schema-backup (13 funktioner + 43 policies →
  `docs/db-backups/2026-06-29-prod-red-functions-policies.sql`), begge RPC'er deployet mod prod +
  grant-loop re-kørt (kaldbare af `authenticated`), rollback-test bestået (FK-ordnet slet rydder
  al evidens uden orphans; dup-guard returnerer samme id; 4 valideringer afviser ugyldig
  objekt_type/ikke-eksisterende objekt) — alt i rollback-txn, nul mutation mod prod data.
* **Udestår:** kun manuel web-e2e (klik gennem editor). Bredere cache-invalidering efter relation-write
  (public person / gods-ejer-tidslinje / 2C-1 ownerCount stale til model-reload) er spec §9-follow-up.


## Plan 2C-1 — entitetslister (read-only) i redaktions-appen (2026-06-28)
* **Hvad:** Entiteter-tab er nu en type-menu med 6 typer (Personer · Godser · Kilder ·
  Organisationer · Medier · Våben), hver med tæller → read-only liste. Personer åbner 2A-listen →
  editor; de øvrige er read-only browse (ingen entitets-write-RPC'er endnu = 2C-2/2C-3).
* **Data:** `buildAux` udvidet med fem flade lister (`kilde/org/medie/gods/vaabenListe`) fra de rå
  arrays den allerede modtager + ét nyt `coat_of_arms`-fetch (våben). Læses fra redaktion-modellens
  aux (2B) — ingen ekstra fetch for de fire. `godsListe` er komplet (inkl. ejerløse godser, modsat
  `estateList`); ejer-tæller bevaret.
* **Auth-state:** lister/menu viser "Kræver redaktør-rolle" for ikke-redaktører (Codex fangede at de
  ellers ville sidde fast på "Henter…" permanent). "Henter…" kun under redaktør-load.
* **Korrektion (Codex):** `coat_of_arms` (våben) FINDES — tidligere fejlpåstand om manglende tabel
  rettet; våben inkluderet. `majorat` korrekt udeladt (en `slags` af estate, ingen egen tabel).
* **Review:** Codex-spec-review (auth-state + våben) + per-task spec+quality. 104/104 jest, tsc rent.
  Relations-redigering = 2C-2; entitets-write + detail-editor = 2C-3.


## Plan 2B — editor-dybde: selv-forsynende editor + køn + familie/sektion (2026-06-28)
* **Hvad:** Person-editoren åbner nu for ALLE personer inkl. de 70 levende (før: "Personen blev
  ikke fundet" fordi den lænede sig på den delte anon-model på 893). Tilføjet: køn-editor
  (redigerbar: mand/kvinde/ukendt → `red_set_koen`), familie (forældre/ægtefæller/børn) +
  sektioner (hverv/godser/kilder) **read-only**.
* **Separat redaktion-model:** ny store-slice (`redaktionModel`/`redaktionAux`) loades via
  redaktion-sessionen (`loadFromSupabase({includePrivat:true})` → 963 inkl. levende, getAll-
  pagineret), adskilt fra publikums-modellen → ingen GDPR-læk i publikums-faner. Editoren bruger
  de EKSISTERENDE selektorer (`parentsOf`/`childrenByMarriage`) + aux uændret → ingen divergens
  fra publikums-visningen (Codex-aligned, se decisions).
* **Narrativ-privat-fix:** `fetchPersonNarrativ` henter første narrativ by id (= præcis skrive-
  målet for `red_upsert_narrativ`) og editoren bevarer privat-flaget på Gem — før kunne en privat
  bio overskrives + gøres offentlig (Codex 2B #1).
* **Privat-toggle** initialiseres nu fra `person.privat` (før hardkodet false). `AppPerson.privat`
  tilføjet; publikums-load uændret default.
* **Review:** Codex-spec-review (skiftede arkitektur fra per-person re-derivation → separat model,
  fangede pagination + familie/hverv-divergens + narrativ-tab) + per-task spec+quality + idle-race-
  fix. 100/100 jest, tsc rent. Relations-redigering + medier + generisk editor = 2C.


## Plan 2A — person-liste & navigation i redaktions-appen (2026-06-28)
* **Hvad:** Entiteter-tab'en har nu en rigtig person-liste (søg + alfabet-hop + alfabetisk/fødeår-sort)
  → tap → person-editor. Dashboardets "Personer"-celle navigerer dertil. Løser URL-tastnings-smerten
  (ingen in-app-vej til en person → web-reload → skrivemode nulstillet).
* **Separat redaktion-fetch:** ny `fetchRedaktionPersoner` (mobile/src/data/redaktionRead.ts) henter ALLE
  personer inkl. levende/privat via redaktion-sessionen — **pagineret** (genbrug `getAll`/`.range`,
  PostgREST capper ved 1000 lydløst). Den delte publikums-model (`load.ts`) røres ikke → ingen GDPR-læk
  i publikums-faner. Verificeret live: redaktion ser 963, anon 893 (70 levende skjult fra publikum).
* **DRY:** `buildSearch` refaktoreret til pool-baseret `searchPool` (genbrugt af publikum + redaktion);
  publikums-`search.tsx` uændret.
* **Tags:** levende/privat-personer markeres i listen ("levende"/"privat"). `born` udledes direkte af
  visning_foedt (ikke dødsår — Codex 2A M1). Fejl-tilstand i listen (ikke tom-som-clean — cycle 03 NEW1).
* **Review:** Codex-review af spec (pagination + born-sort indarbejdet før impl); per-task spec+quality.
  94/94 jest, tsc rent. Andre entiteter + generisk editor = 2C; køn/familie-visning = 2B.


## Redaktions-UI kerne-skive — implementeret + DB-deploy (2026-06-27)
* **Hvad:** Vertikal kerne-skive af redaktør-appen (mobil editor): `redaktion/`-route-segment
  med native `(red-tabs)`-navigation, dashboard (rolle-kort + dry-run + konflikt-kø +
  entitets-grid), person-editor (evidens-lag: kerne-fakta navn/foedt/doed/titel med
  konklusion←oplysninger, redigér/slet/gør-til-konklusion/tilføj via inline-editor + narrativ),
  konto + login-sheet, skrive-preview-sheet (dry-run/live) og slet-bekræft m. cascade-advarsel.
* **Nyt evidens-read-lag** (`mobile/src/data/redaktionRead.ts`): `fetchPersonEvidence` henter
  den polymorfe model (fact/assertion/conclusion/citation) som N flade queries + klient-join
  (target_type/target_id har ingen FK → nested-select 400'er; citation→source nestes via FK).
  `fetchKonflikter` (konflikt-kø) + `fetchSletPreview` (cascade).
* **Write-lag udvidet** (`redaktionWrite.ts`): `buildRpcCall`-cases for redigerOplysning/
  sletOplysning/setKonklusion/setPrivat/sletPerson + `oversaetFejl` (dansk). Alle writes via
  én path (dry-run preview ELLER live RPC); cache regenereres af DB-trigger.
* **DB additivt (deployet live 2026-06-27):** `red_konflikt`-view (`security_invoker=true` —
  KRITISK, ellers omgår viewet RLS og lækker private personers konflikter); redaktion-read-RLS
  (rolle=redaktion ser private rækker, så privat-toggle ikke låser redaktøren ude);
  `red_slet_person_preview`-RPC (cascade-advarsel der spejler red_slet_person's indgående+udgående
  relations-slet). Backup taget før deploy (`~/daa-backup-20260627-redaktion-ui.sql`).
  Live-verificeret: view returnerer konflikt-rækker, RPC rolle-gated (P0001), privat-læk lukket (anon ser 0 private).
* **Review:** Codex-review af spec (8 fund indarbejdet før impl); per-task spec+quality-review;
  final whole-branch review (opus) READY — RPC-kontrakt app↔DB, evidens-join, GDPR/RLS,
  write-data-flow alle verificeret rene. 81/81 jest grøn, tsc rent.
* **Udestår (plan 2, bevidst):** køn-editor i UI (red_set_koen-path findes+testet, intet kort);
  familie/sektioner read-only-visning; entitetslister; generisk record-editor; opret-flow;
  relations/sektion-redigering. Operationelt: seed en `redaktion`-profil (auth.users +
  profiles.rolle='redaktion') for at teste happy-path-writes mod live; manuel e2e på device.

## `levende`-GDPR-cache udledt + RLS-deploy-bug rettet (2026-06-25)
* **Root cause:** `load_daa.R:64` hardkodede `levende=FALSE` på hver person — flaget
  blev aldrig udledt. Alle 963 stod FALSE, inkl. nulevende (fx Johan Martin, id 488,
  f. 1977). Med RLS aktiv ville selv korrekt filter eksponere dem.
* **Regel (bruger):** levende = født inden for seneste 100 år (ift. load-dato) UDEN
  død/begravelse/dødsårsag-fakta og uden `visning_doed`. Fail-closed: ukendt fødselsår
  → FALSE (de udaterede er tidlige aner). Udledt fra **struktureret** fødedato
  (`assertion.date_min/max` via blåstemplet `conclusion`), ikke display-cachen.
* **Backfill (live, committet):** 70 personer → `levende=TRUE`. To uafhængige metoder
  (display-regex + struktureret fakta) konvergerede på præcis 70; risiko-bucket (166 uden
  fødsels/død-fakta) verificeret til 0 levende (alle tidlige aner; edge-case id 940 =
  1785-ægtefælle). `load_daa.R` fået derivations-pass så næste load ikke nulstiller.
* **`db-rls.sql`-bug:** oprettede `anon_read` men droppede ALDRIG den midlertidige
  `dev_anon_read` (USING true). Postgres OR'er permissive politikker → deploy as-is =
  fuld læk (anon ser alle 70 levende). Verificeret via transaktionel sim mod live
  (apply → SET ROLE anon → tæl → ROLLBACK): A=70 lækket, B (dev droppet)=0. Rettet:
  `db-rls.sql` dropper nu `dev_anon_read` på alle tabeller først. Re-sim: 0 lækket,
  893 afdøde + data loader stadig (narrative 550, relation 961, family_member 1205).
* **Deployet mod live (2026-06-25):** `db-rls.sql` kørt via `work/rls_deploy.R`
  (verificer-og-commit). Verificeret som anon: 893 afdøde synlige, 0 levende lækket,
  helper-fn på plads, `dev_anon_read` væk. anon-tier GDPR-lag er nu aktivt i prod.
* **Udestår:** `authenticated`-tier (medlem/forsker ser levende slægtninge m. samtykke)
  — skitse nederst i `db-rls.sql`, bygges når login/profiles er på plads. `media`-tabel
  er deny-all indtil afbildet-gating skrives (tom nu).

## Slægtslinjer navngives — `lineage`-entitet, trin (a) (2026-06-23)
* Linjer levede kun som bart `'I'..'V'`-token på `person_external_id.linje`. Ny entitet
  `lineage(id, source_id, kode, navn, UNIQUE(source_id,kode))` giver dem navne:
  I=Den holstenske linje, II=Linjen Gallentin, III=Den mecklenburgske linje,
  IV=Den lensgrevelige linje af 1767, V=Den grevelige linje af 1673.
* `schema.sql` (source of truth) + idempotent migration i `db-migrations.sql`. Backfill
  er **data-drevet**: `source_id` + `kode` udledes via `SELECT DISTINCT` fra
  `person_external_id` (ingen hardcodet source-id); `ON CONFLICT DO NOTHING` → re-kørbar.
* App (`mobile/`): `load.ts` henter `lineage` (tolerant `.catch(()=>[])` indtil migration
  kørt), `buildAux.ts` bygger `linjeNavn`-map + `navn` på `linjeList`. UI viser navn med
  fallback til `Linje {kode}`: linje-chips (tree), gen-header (VariantC), persondetalje-badge.
* **Trin (b) bevidst udskudt:** adling→ny slægt, forgrening (`gren_af`), eget våben,
  person↔linje m. konfidens. Tabellen er forward-kompatibel — (b) er ren `ALTER ADD` +
  relationer senere. Se `docs/decisions.md` + datamodel-oversigt §5/§9.
* Tests: `buildAux.test.ts` udvidet (navn-map, fallback til null, bagudkompatibilitet);
  8/8 grøn, `tsc --noEmit` ren.
* **Udestår:** migrationen er IKKE kørt mod live-basen endnu (auto-mode blokerede
  produktions-skrivning); runner klar i `/tmp/run_lineage.R`.

## Ægtefælle-rygrad for hele slægten + deterministisk boern (2026-06-17)
* Re-load af hele stamtavlen med ægtefælle-rygrad for HELE slægten (ikke kun nær
  familie): 591 poster → 925 personer (591 hoved + 334 ægtefæller). Backup-dump af
  forrige base gemt (`work/dump_before_reload_*.rds`, 22.702 rækker).
* Loader-fixes: `sp_date()` tåler nu både struktureret (object) og rå string
  partner-datoer (udtræk var inkonsistent: 198 string vs 29 object for fødsel);
  ægtefælle-bio-note flyttet fra person til `family` (så appen viser den);
  begivenheder uden navn skippes + fallback-rolle "deltager".
* **`boern` udledes nu DETERMINISTISK** i `validate.py` (`derive_boern`) — LLM-trinnet
  missede børne-referencer systematisk (Codex fangede 38/123). Regex hærdet mod alle
  fraseringer (plural sønner/døtre, "?"-markør, "5 (7?) børn", bar "børn:", linjebrudt
  range). Fanger 123 ægte, afviser hallucinerede uden tekst-belæg.
* Bugs fundet+fixet: forkerte forældre (dato-linje læst som post-header i ad-hoc patch);
  manglende ægtefælle-info (string-datoer ej parset).
* Undersøgt: 145 kryds-gren-tvetydige boern-links (`boern.linje` = bogens interne
  gren-tæller, IKKE JSON-linje). 97 verificerede fejl, 38 ægte kryds-gren. Era-tie-break
  anbefalet (next-step). Rammer også linje V (fx V-73→V-106).

## App-skive + slægtskabs-UI (2026-06-15/16)
* Minimal Vite/React/Supabase-app der renderer lagdelte evidens-data.
* Relations-visning centreret på en fokus-person (forældre/søskende/ægtefælle/børn),
  klikbar graf-navigation; start på Johan Martin (V-186).
* Viser: lagdelte fakta (vaerdi + dato), dekoration (hvilken · hvornår), fuld narrativ,
  vielsesdato(er) + skilsmisse på ægtefælle-kort, ægtefælle-bio-noter + person-fakta.
* s.å./s.m. ekspanderes i visning via opløst ISO-dato (rå tekst bevaret i basen).
* Midlertidig dev-RLS udvidet til alle læse-tabeller (erstattes af rigtigt RLS-lag).

## DAA-parsere som skills (2026-06-15)
* `/daa-extract` — stamtavle-PDF → evidensmodel. Pipeline: pdftotext → segment.py
  (deterministisk) → LLM-udtræk → blokerende validering → R bulk-load.
* `/daa-presens` — præsensliste (nulevende medlemmer, OCR-tolerant, relations-træ).
* Segmentering håndterer: gren-headere (DEN…LINJE + LINJEN GALLENTIN), per-linje
  løbenr, under-numre (15a/b/c), ?-præfiks (usikkert medlemskab → konfidens).

## Datamodel + load (2026-06-15/16)
* Fuld Reventlow-stamtavle loadet: 591 poster → 934 personer (Sonnet-udtræk).
* Evidenslag på relationer (ikke kun fakta); steder normaliseret til `place`;
  ejendom/org/begivenhed dedupes (get-or-create); ægteskab → familie-fakta.
* Bulk-insert loader (dbAppendTable/COPY): 30+ min, skrøbelig → ~14 sek, pålidelig.
* Indekser på relations-/evidens-opslag. Kontrolleret vokabular (vocab) + V9-validering.
* Forkortelsesnøgle (bogens bagstof) seedet i vocab(scheme='forkortelse').
* Nær families ægtefæller (V-175/186/187/188/199) beriget: fødsel/dåb/død + bio-note.
* erhverv/uddannelse holdt UDE af rygrad (ligger i narrativ/bio-note).

## TNG-analyse (2026-06-15)
* `jr_tng_reventlow.sql` (25k personer) analyseret som senere enrichment-kilde;
  gaps dokumenteret i docs/tng-reventlow-analyse.md (git-ignoreret, levende-data).

## Kendte issues / næste
* Haiku-fuld-broaden af ægtefælle-rygrad FEJLEDE (parallelle agenter clobberede delt
  output-mappe) — ingen data tabt, men ~10% kvote spildt. Genoptag KUN med isolerede
  output-mapper/worktrees + terse agent-output. Se memory parallel-agenter-isoleret-output.
* RLS-lag (rigtigt) mangler — kritisk før multi-bruger pga. nulevende-data.
* Dekorations-nøgle hentes fra anden DAA-udgave (koder bevaret rå).
* ~16% relative datoer uopløst ved udtræk (rå tekst bevaret).
