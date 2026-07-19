# Dokumentationsindeks

Digital følgesvend til Danmarks Adels Aarbog (PoC: familien Reventlow). Denne fil
sorterer dokumentationen efter *hvad den er til* — så gældende arkitektur ikke drukner
i historiske planer og afsluttede reviews.

---

## 📌 Læs disse først

| Dokument | Hvad |
|---|---|
| [`../claude.md`](../claude.md) | Projekt-handoff: vision, arkitektur, invarianter (§3 er ufravigelige), aktuel tilstand. |
| [`../datamodel-oversigt.md`](../datamodel-oversigt.md) | **Autoritativ** konceptuel modelbeskrivelse — *hvorfor* modellen ser sådan ud. |
| [`database-current-state.md`](database-current-state.md) | **Hvad er faktisk i prod nu** + hvilke SQL-filer der er autoritative + deploy-procedure. |

## 🟢 Aktuel status & løbende log

| Dokument | Hvad |
|---|---|
| [`changelog.md`](changelog.md) | Kronologisk log: hvad ændrede sig, fejl fanget, reviews, testniveau, prod-status. Nyeste øverst. |
| [`decisions.md`](decisions.md) | Arkitektur-beslutningslog: ikke-oplagte valg + hvorfor alternativer blev fravalgt. |

## 🗄️ Skema & database (autoritative filer i repo-roden)

| Fil | Rolle |
|---|---|
| [`../schema.sql`](../schema.sql) | Source of truth for hele skemaet. |
| [`../db-migrations.sql`](../db-migrations.sql) | Idempotente additive migrationer oven på en deployet base. |
| [`../db-rls.sql`](../db-rls.sql) | RLS-lag (anon-tier live; se `database-current-state.md`). |
| [`../db-verify.sql`](../db-verify.sql) | Adfærds-verifikation (asserts efter deploy). |

## 🔧 Data-pipelines

| Dokument | Hvad |
|---|---|
| [`daa-extraction-archetype.md`](daa-extraction-archetype.md) | `/daa-extract` — parser DAA-stamtavle-PDF → datamodel. |
| [`../.claude/skills/daa-haendelser/SKILL.md`](../.claude/skills/daa-haendelser/SKILL.md) | `/daa-haendelser` — GDPR-filtreret narrativ-eksport → LLM-udtræk → H1–H8-validering → bevarelses-mergende hændelses-load. |
| [`daa-presens-archetype.md`](daa-presens-archetype.md) | `/daa-presens` — parser præsensliste (nulevende medlemmer). |
| [`tng-qa-koersel.md`](tng-qa-koersel.md) | TNG-QA-pipeline (`R/tng-qa/`): read-only QA af relationer/datoer mod et TNG-dump. |

## 🗺️ Roadmaps

| Dokument | Hvad |
|---|---|
| [`plan-1939-produktionsklar.md`](plan-1939-produktionsklar.md) | **🔴 Aktiv styringsplan:** 1939-load + dato-hærdning + Fase 4-cutover. Prioriteret efter prod-gate (Spor A ubblokeret nu · Spor B gated · Konvergens). |
| [`moed-en-slaegtning-roadmap.md`](moed-en-slaegtning-roadmap.md) | Telefon-til-telefon slægtskab ved fysisk møde (QR → BLE → UWB). |
| [`flere-daa-udgaver-roadmap.md`](flere-daa-udgaver-roadmap.md) | Præsenslister over tid, modstridende relationer mellem udgaver, tværudgave-personidentifikation. |

## 🎨 Design & koncepter (levende — styrer kommende udvikling)

| Dokument | Hvad |
|---|---|
| [`design/2026-07-19-mediehaandtering-robust-koncept.md`](design/2026-07-19-mediehaandtering-robust-koncept.md) | **Robust mediehåndtering** (koncept, ingen kode): Wikimedia-inspireret medieforvaltning for redaktionen — filside pr. medie, mediebibliotek med arbejdskøer, livscyklus (genopret/udrens), rettigheds-workflow-UI, erstat-fil, dedup-aktivering. 11 mangler (M1–M11), 4 faser; bygger videre på medieplanen 2026-07-04 (Slice 0–5). |
| [`design/2026-07-18-levende-feed-koncept.md`](design/2026-07-18-levende-feed-koncept.md) | **Det levende feed:** dynamik (seeded sampling), ægte uendelig scroll, hændelses-skelet + minihistorier (formidlingslag), redaktionel kuratering, LLM-assist. 4 faser; afløser feed v3-spec'ens statiske model. **Fase 1–3 er implementeret og lokalt verificeret** ✅. Fase 2/3's Supabase-/prod-trin er fortsat gatede. |
| [`superpowers/specs/2026-07-19-levende-feed-fase3-design.md`](superpowers/specs/2026-07-19-levende-feed-fase3-design.md) | **Fase 3-spec:** minihistorier, `story_kilde`, feed-pins, redaktionel styring og web-startpersoner. Implementeret efter [fase 3-planen](superpowers/plans/2026-07-19-levende-feed-fase3.md); automatisk og lokal PostgreSQL-verifikation er grøn, mens rigtig Supabase/PostgREST og prod-migration fortsat er deploy-gates. |
| [`design/2026-07-18-formidlingskatalog.md`](design/2026-07-18-formidlingskatalog.md) | **Idékatalog** (ikke besluttet): 19 formidlingsidéer oven på kildematerialet — evidens-formidling, serier/udstillinger, kort/sted, personalisering, objekter, distribution, leg. Med grundlag/afhængigheder/indsats pr. idé + prioriteringsbillede. |
| [`design/2026-07-08-web-navigation-soegning-stamtrae-koncept.md`](design/2026-07-08-web-navigation-soegning-stamtrae-koncept.md) | Web: mega-menu-navigation, søgning i stamtræet, split-skærm flade+detalje. (§9.f forsidens form er lukket af feed-konceptet ovenfor.) |

---

## 🗂️ Historiske artefakter (kontekst, ikke gældende sandhed)

Afsluttede planer, specs og reviews. Værdifulde som *hvorfor blev det gjort sådan*,
men **ikke** kilde til aktuel tilstand — brug changelog + `database-current-state.md` til det.

- **`reviews/`** — afsluttede review-runder (dual-review Claude+Codex, QA-rapporter).
  Fx `09-versionering-hyperlinks-db.md`, `10-app-lag-hyperlinks.md`.
- **`superpowers/plans/`** — implementeringsplaner (én pr. feature, tidsstemplet).
- **`superpowers/specs/`** — design-specs der gik forud for planerne.
- **`tng-qa-rapport-<dato>.md`** (i `reviews/`) — genererede QA-rapporter (GDPR-gated output).

---

## App-lag

- **`../mobile/`** — React Native / Expo-app (redaktør + publikum). Se [`../mobile/README.md`](../mobile/README.md).
- **`../web/`** — web-skive (TypeScript/React + Supabase).
