# Dokumentationsindeks

Digital følgesvend til Danmarks Adels Aarbog (PoC: familien Reventlow). Denne fil
sorterer dokumentationen efter *hvad den er til* — så gældende arkitektur ikke drukner
i historiske planer og afsluttede reviews.

---

## 📌 Læs disse først

| Dokument | Hvad |
|---|---|
| [`evidensbaseret-genimport/vision.md`](evidensbaseret-genimport/vision.md) | Autoritativ vision og værdigrundlag for DAA-import og -genimport. |
| [`evidensbaseret-genimport/roadmap.md`](evidensbaseret-genimport/roadmap.md) | Det styrende roadmap: bindende prioritering og seks adgangskrav til nye planer. |
| [`evidensbaseret-genimport/teknisk-maalarkitektur.md`](evidensbaseret-genimport/teknisk-maalarkitektur.md) | Autoritativ teknisk målarkitektur for den fælles ende-til-ende-kæde; levende kode og schema afgør aktuelle detaljer. |
| [`evidensbaseret-genimport/status.md`](evidensbaseret-genimport/status.md) | Aktuel status og statusorakel for genimportprogrammets mål, modenhed og næste tilladte arbejde. |
| [`../CLAUDE.md`](../CLAUDE.md) | Projekt-handoff: arkitektur, invarianter og agentinstruktioner. |
| [`../datamodel-oversigt.md`](../datamodel-oversigt.md) | Autoritativ bred konceptmodel — *hvorfor* modellen ser sådan ud. For source-record-, narrativ- og genimportproveniens styrer [`evidensbaseret-genimport/teknisk-maalarkitektur.md`](evidensbaseret-genimport/teknisk-maalarkitektur.md). |
| [`database-current-state.md`](database-current-state.md) | Autoritet for senest dokumenterede live-prod-tilstand, autoritative SQL-filer og deploy-procedure; driftfølsomme spørgsmål kræver altid en frisk kontrol. |

## 🟢 Beslutninger og løbende historik

| Dokument | Hvad |
|---|---|
| [`changelog.md`](changelog.md) | Kronologisk historik over ændringer, fejl, reviews og testniveau; ikke aktuel programstatus. |
| [`decisions.md`](decisions.md) | Arkitektur-beslutningslog: ikke-oplagte valg + hvorfor alternativer blev fravalgt. |

## 🗄️ Skema & database (autoritative filer i repo-roden)

| Fil | Rolle |
|---|---|
| [`../schema.sql`](../schema.sql) | Source of truth for hele skemaet. |
| [`../db-migrations.sql`](../db-migrations.sql) | Idempotente additive migrationer oven på en deployet base. |
| [`../db-rls.sql`](../db-rls.sql) | RLS-lag (anon + almindelig authenticated fail-closed; se `database-current-state.md`). |
| [`../db-verify.sql`](../db-verify.sql) | Adfærds-verifikation (asserts efter deploy). |
| [`runbooks/`](runbooks/) | Prod-ceremonier (DDL/data-overførsler, rehearsal, fortrydelse). Aktuel: [`transfer-5ab-ddl-prod.md`](runbooks/transfer-5ab-ddl-prod.md) (5a+5b, GO 1). |

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
| [`plan-1939-produktionsklar.md`](plan-1939-produktionsklar.md) | Historisk plan for cutover/1939-load; ikke gældende styring eller aktuel status. Brug genimportens roadmap og statusorakel ovenfor. |
| [`moed-en-slaegtning-roadmap.md`](moed-en-slaegtning-roadmap.md) | Telefon-til-telefon slægtskab ved fysisk møde (QR → BLE → UWB). |
| [`flere-daa-udgaver-roadmap.md`](flere-daa-udgaver-roadmap.md) | Historisk og ikke-styrende roadmap for flerudgaveidéer; underordnet genimportens styrende roadmap og statusorakel ovenfor. |

## 🎨 Design & koncepter (levende — styrer kommende udvikling)

| Dokument | Hvad |
|---|---|
| [`design/2026-07-19-mediehaandtering-robust-koncept.md`](design/2026-07-19-mediehaandtering-robust-koncept.md) | **Robust mediehåndtering:** fase 1–2 er implementeret og lokalt/CI-verificeret, men ikke prod-deployeret; fase 3–5 dækker hygiejne/dedup, identitet/udrensning og dokumenttransskription. |
| [`design/2026-07-18-levende-feed-koncept.md`](design/2026-07-18-levende-feed-koncept.md) | **Det levende feed:** dynamik (seeded sampling), ægte uendelig scroll, hændelses-skelet + minihistorier (formidlingslag), redaktionel kuratering, LLM-assist. 4 faser; afløser feed v3-spec'ens statiske model. **Fase 1–3 er implementeret og lokalt verificeret** ✅. Fase 2/3's Supabase-/prod-trin er fortsat gatede. |
| [`superpowers/specs/2026-07-19-levende-feed-fase3-design.md`](superpowers/specs/2026-07-19-levende-feed-fase3-design.md) | **Fase 3-spec:** minihistorier, `story_kilde`, feed-pins, redaktionel styring og web-startpersoner. Implementeret efter [fase 3-planen](superpowers/plans/2026-07-19-levende-feed-fase3.md); automatisk og lokal PostgreSQL-verifikation er grøn, mens rigtig Supabase/PostgREST og prod-migration fortsat er deploy-gates. |
| [`design/2026-07-18-formidlingskatalog.md`](design/2026-07-18-formidlingskatalog.md) | **Idékatalog** (ikke besluttet): 19 formidlingsidéer oven på kildematerialet — evidens-formidling, serier/udstillinger, kort/sted, personalisering, objekter, distribution, leg. Med grundlag/afhængigheder/indsats pr. idé + prioriteringsbillede. |
| [`design/2026-07-08-web-navigation-soegning-stamtrae-koncept.md`](design/2026-07-08-web-navigation-soegning-stamtrae-koncept.md) | Web: mega-menu-navigation, søgning i stamtræet, split-skærm flade+detalje. (§9.f forsidens form er lukket af feed-konceptet ovenfor.) |

---

## 🗂️ Historiske artefakter (kontekst, ikke gældende sandhed)

Afsluttede planer, specs og reviews. Værdifulde som *hvorfor blev det gjort sådan*,
men **ikke** kilde til aktuel programstatus. Brug
`evidensbaseret-genimport/status.md`; kontrollér live prod frisk via
`database-current-state.md` og de autoritative SQL-filer ved driftfølsomme spørgsmål.

- **`reviews/`** — afsluttede review-runder (dual-review Claude+Codex, QA-rapporter).
  Fx `09-versionering-hyperlinks-db.md`, `10-app-lag-hyperlinks.md`.
- **`superpowers/reviews/2026-08-22-evidensbaseret-genimport-afvigelsesvurdering.md`**
  — historisk afvigelsesvurdering og review-kontekst, ikke aktuelt statusorakel.
- **`superpowers/plans/`** — implementeringsplaner (én pr. feature, tidsstemplet).
- **`superpowers/specs/`** — design-specs der gik forud for planerne.
- **`tng-qa-rapport-<dato>.md`** (i `reviews/`) — genererede QA-rapporter (GDPR-gated output).

---

## App-lag

- **`../mobile/`** — React Native / Expo-app (redaktør + publikum). Se [`../mobile/README.md`](../mobile/README.md).
- **`../web/`** — web-skive (TypeScript/React + Supabase).
