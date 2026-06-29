# Changelog

## Plan 2C-2b — redigerbar familie-sektion (partner + barn + konfidens) i redaktør-person-editoren (2026-06-29)
* **Hvad:** Redaktøren kan nu tilføje og afkoble ægtefælle/partner, tilføje og afkoble børn
  samt justere konfidens på familie-links direkte i person-editoren — alt via det eksisterende
  SkrivePreviewSheet-gate (dry-run → live). HVERV/GODSER/KILDER er uændrede fra 2C-2a.
* **4 nye SECURITY DEFINER RPC'er (udestår i prod — controller-gate):**
  - `red_opret_union(p_partner_a, p_partner_b, p_type, p_ordinal)` — opretter ny family-entitet
    + 2 partner-links. INGEN auto-dedup: samme par kan gifte sig igen — par-dedup ville flette
    børn og event-tidslinjer fra to selvstændige ægteskaber (Codex H2). partner_a==b og ugyldig
    type afvises med RAISE.
  - `red_tilfoej_barn(p_family_id, p_barn_id, p_rolle, p_konfidens)` — tilføjer barn-link til
    eksisterende family. Cyklus-guard via recursiv CTE: tilføjer en ane som barn → RAISE (Codex H3).
    Selv-forælder (barn==en af familiens partnere) afvises. PK-dublet = no-op. Ugyldig
    rolle/konfidens afvises.
  - `red_set_familie_konfidens(p_family_id, p_person_id, p_konfidens)` — UPDATE
    `family_member.konfidens` for præcist ét link; ukendt link → RAISE; ugyldig konfidens → RAISE.
  - `red_slet_familie_link(p_family_id, p_person_id)` — sletter KUN `family_member`-rækken.
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
  (SletBekræft → sletFamilieLink). FORÆLDRE-sektionen er read-only (ingen slet-forælder-RPC).
* **Test:** 121/121 jest, tsc rent.
* **Udestår (controller-gate):** live RPC-deploy mod prod, rollback-tests, manuel web-e2e.


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
