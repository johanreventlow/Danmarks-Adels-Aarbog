# Changelog

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
