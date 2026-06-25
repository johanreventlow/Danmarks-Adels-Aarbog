# Changelog

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
* **Udestår:** `db-rls.sql` er IKKE deployet mod live endnu (auto-mode blokerede
  produktions-skrivning); runner klar i `work/rls_deploy.R` (verificer-og-commit:
  COMMIT kun hvis 0 lækket). Live kører stadig dev-permissivt (alt offentligt) indtil da.

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
