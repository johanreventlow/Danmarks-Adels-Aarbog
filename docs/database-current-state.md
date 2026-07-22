# Database — Current State (operatør-guide)

> **Formål:** Ét sted der siger, hvad der faktisk er i prod nu, hvilke SQL-filer der
> er autoritative, og hvordan næste deploy forberedes sikkert. Changelog fortæller
> historien; denne side fortæller tilstanden.
>
> **Sidst afstemt:** 2026-07-20 (live-objektinventar kørt direkte mod prod via Supabase MCP,
> ikke kun mod changelog). Opdatér ved hver prod-deploy. Ved uenighed med ældre planer/specs
> gælder denne side for prod-status; ret derefter det forældede dokument i dets egen
> dokumentationsrunde.
>
> **Fund ved 2026-07-20-afstemningen:** denne sides "Sidst afstemt: 2026-07-01" havde stået
> ureflekteret i tre uger. Et direkte objektinventar (tabeller + `pg_proc`-funktionsnavne)
> viste at ALT arbejde dateret 2026-07-02 til 2026-07-17 i `db-migrations.sql`/`db-rls.sql`
> (samme_som/ikke_samme_som, udledt slægtsnavn, dato-hærdning, Problem 2 forældrefamilie-fase 1,
> K2 staging-gate m.fl.) reelt VAR live i prod — blot aldrig dokumenteret her. Kun tre
> ting manglede reelt: `haendelse`-tabellen (levende feed fase 2), `story`/`story_kilde`/
> `feed_pin` (levende feed fase 3) og `red_publicer_personer` (K2 selektiv publicering,
> selv samme dag). Alle tre er nu deployet (se §2). **Læring:** stol ikke på denne sides
> dato uden et faktisk objekt-tjek ved næste afstemning — dokumentationsdrift er reel.

---

## 1. Verificeret prod-snapshot 2026-07-20

| Område | Faktisk tilstand |
|---|---|
| Personer | **1.758** total; **835 staged**; **77 levende**; 0 `privat=TRUE` |
| Offentlig/medlem | `anon` og almindelig `authenticated` ser begge **853 personer**, **0 levende**, **0 staged** |
| Kilder | 3 source-rækker. Source 1 = DAA 2018-20/2020 med 591 direkte poster; source 3 = DAA 1939/1939 med 539 direkte poster |
| Slægtskab | 2.224 `family_member`-rækker; **921** `forældrefamilie`-facts |
| Medier | **6** media-rækker: 2 `klar`, 4 `fjernet`; privat `media`-bucket og `media_variant` findes |
| Bogmærker | `bookmark` er live og indeholder 1 række |
| Versionering | 22 tabeller i `version_pk_registry`; `change_set`/`change_event` og `text_mention` er live |
| API-sikkerhed | `anon` og `authenticated` har ikke EXECUTE på `_delete_relation_evidence(bigint)`; public-schemaet har 63 RLS-politikker |

Tallene er et øjebliksbillede og kan drive. Synligheds- og objekttilstedeværelses-
asserts er de vigtigste driftsinvarianter; opdatér snapshotdato og tal ved næste
prod-deploy.

---

## 2. Autoritative repo-filer

| Fil | Rolle | Prod-brug |
|---|---|---|
| `schema.sql` | Source of truth for ønsket clean-slate-skema. Indeholder også endnu ikke deployede faser. | Kun frisk base; er **ikke** bevis for prod-status |
| `db-migrations.sql` | Kumulativ additiv migrationssti mod en eksisterende base. Indeholder både live og endnu ikke deployede blokke. | Kun efter backup + rehearsal; brug den præcist godkendte sti/blok |
| `db-rls.sql` | Samlet RLS-/grant-definition. Migrationer genanvender den ikke automatisk. | Genanvend efter relevante DDL-ændringer og verificér roller |
| `db-verify.sql` | Muterende adfærdsasserts med fixtures. Flere blokke er miljø-/dataafhængige. | Kør scoped efter runbook; ikke ukritisk som én samlet prod-fil |
| `db-verify-media.sql` | Media-/Storage-RLS-asserts. Rigtig Supabase har `storage.protect_delete`, som lokal shim ikke spejler fuldt. | Brug mod kopi eller med særskilt godkendt prod-testflow |
| `db-rollback-fase3.sql` | Kirurgisk rollback af tomt fase 3-feedlag; afbryder ved fase 3-data/-historik. | Kun efter fuld backup; ikke deployet eller prod-rehearsed |

`supabase_load.R` i repo-roden er historisk. Nye DAA-loads går gennem
`.claude/skills/daa-extract/scripts/load_daa.R`, normalt append/staged og aldrig
`--reset` mod en befolket prod-base.

---

## 3. Hvad er live i prod

### Kerne, evidens og Fase 4-cutover

- Evidensmodellen `fact` → `assertion` → `citation`/`conclusion`, generiske
  relationer, lineage og personens `visning_*`-cache er live.
- Problem 2-cutoveret er live: `assertion.objekt_type/objekt_id`, fødselsfamilie-
  constraint, `forældrefamilie`-slots og redaktions-RPC'erne til konkurrerende
  forældrepåstande findes. De 921 slots svarer til de to loadede udgavers valgte
  forældrefamilier.
- A1-datohærdningen er live: bl.a. `assertion.date_certainty` og calendar-bæring.
- K2-staging er live: `person.staged`, `person_offentlig`-gaten og
  `red_publicer_udgave(bigint)` findes.
- F-01/F-02/F-02c-hærdningen er live: interne mutatorer er fjernet fra den offentlige
  API-flade, og almindelig `authenticated` er fail-closed til samme personregel som
  `anon`. Levende/staged kræver fortsat redaktionsadgang.

### 1939: loadet staged, men publicering er pauset

- DAA 1939 er loadet som source 3 med 835 staged personer (539 direkte poster +
  partnerstubs). De er usynlige for `anon` og almindelig `authenticated`.
- **Publicér ikke source 3.** Projektbeslutningen 2026-07-20 er, at 1939-PDF'en skal
  OCR-udtrækkes igen, og at artefakt-/komplethedsgaten skal gentages før videre
  1939-arbejde. Den ældre `plan-1939-produktionsklar.md` dokumenterer det tidligere
  forløb, men er ikke længere handlingsanvisning for publicering.
- En kommende erstatning/opdatering af staged source 3 kræver en særskilt,
  source-scoped plan, backup og rehearsal. Der må hverken appendes en dubletudgave
  eller bruges `--reset`.

### RLS/GDPR

- `anon` og almindelig `authenticated` ser kun afdøde, ikke-private, ikke-staged
  personer og de personbundne rækker, som arver samme gate.
- `entitet_offentlig`/`family_offentlig` lukker polymorfe fakta, relationer,
  narrativer, noter og mentions fail-closed på levende eller ukendte targets.
- Redaktion har et additivt læse-/skrive-lag gennem rolle-gatede RPC'er.
- En fremtidig medlem/forsker-model med samtykke og slægtsscope er ikke implementeret.

### Versionering, hyperlinks og bogmærker

- `change_set`/`change_event`, `log_change`, `red_fortryd_change_set` og 22
  registry-styrede versioneringstriggere er live.
- `parse_mentions`, `text_mention` og døde-links-viewet er live. Media-grenen i
  `red_doede_links` er live som del af mediehåndtering fase 2.
- Konto-bogmærker er live med owner-bundet RLS.

### Mediehåndtering fase 0-2 (live, senest bekræftet 2026-07-20)

- **Slice 0** (bucket, gating, upload-RPC'er) live siden 2026-07-05. **Fase 1** (filside:
  `red_opdater_media`, `red_genopret_media`, kunstner/datering i `red_upload_media`) og
  **fase 2** (bibliotek: `red_doede_links` udvidet med `maal_type='media'`, `text_mention`
  `GRANT SELECT` + korrekt `media_synlig_anon`-gating i `tm_read`) deployet 2026-07-20.
- `media`-afbildet-gating er FULDT AKTIV (ikke deny-all/tom — se rettelse i §3): 6 media-
  rækker i prod (2 `klar`, 4 `fjernet`), `media_variant` populeret.

### Levende feed fase 2-3 + K2 selektiv publicering (deployet 2026-07-20)
- **`haendelse`** (fase 2, regenererbar hændelses-projektion af narrativer) + **`story`/
  `story_kilde`/`feed_pin`** (fase 3, kurateret formidlingslag) — additive tabeller,
  RLS aktiv (anon ser kun `publiceret`+ikke-privat+offentligt-subjekt for story;
  `feed_status<>'skjult'` for haendelse), versioneret via `log_change`.
- **`red_publicer_personer(person_ids[])`**: selektiv modstykke til `red_publicer_udgave`
  — publicerer kun udvalgte 1939-personer (+ familie-partnere) fremfor hele kilden på én gang.
- Deployet direkte via Supabase MCP (`execute_sql`/`apply_migration`), ikke `psql`-runbooken;
  objekt-eksistens + `get_advisors(security)` verificeret efter apply (117 fund, alle kendte
  mønstre — SECURITY DEFINER-eksponering + bevidst deny-all på historik-tabeller — ingen nye).
  **Udestår:** brugerens egen live-røgtest af filside/bibliotek/feed i appen.

---

## 4. Hvad er ikke live / bevidst udskudt

| Emne | Status |
|---|---|
| **RLS `authenticated`-tier** (medlem/forsker ser levende slægtninge m. samtykke) | Kun skitseret i `db-rls.sql` §FREMTID. Bygges når login/profiles-auth er på plads. Indtil da er levende data usynlige for alle uden `redaktion`-rolle. |
| **`max(id)+1` → IDENTITY/sekvenser** | Udskudt post-PoC. Kritisk før flerbruger-skrivning (også multi-writer-risikoen generelt). |
| **Samtykke-granularitet pr. levende person** (`samtykke_offentlig`) | Designes med auth-laget. |
| **Vocab-håndhævelse** | `vocab`-tabel findes, men `rolle`/`faktatype`/`konfidens` m.fl. er fritekst (ingen FK til vocab). Håndhæves i dag kun konventionelt. |
| **Polymorf døde-link-integritetsrapport** | Kun `text_mention` har et døde-links-view. Bredere orphan-check (fact/relation/assertion → subjekt) findes ikke systematisk endnu. |
| Levende feed fase 4 | LLM-assist/Edge Function — bevidst udskudt 2026-07-20 (for få kilder i PoC til at retfærdiggøre kørslen endnu), ikke annulleret. Se `decisions.md`. |
| **Mediehåndtering fase 3 — hygiejne** | Implementeret og verificeret lokalt, men **ikke live i prod**. Det aktuelle `schema.sql` har NULL-bar `media.created_at DEFAULT now()`, det partielle firekolonne-index `relation_afbildet_uidx` for `rolle='afbildet'`, constraint-specifik domænefejl i `red_relation` samt relationsspecifikke evidenstriggere og den atomiske flet-RPC `red_slet_medierelation_uden_evidens`; den scoped blok `mediehaandtering_fase3_hygiejne` i `db-migrations.sql` bringer en fase 1+2-base til samme flade. Web/mobil bruger sha-stier; janitoren er report-first. `db-rls.sql` er uændret af fase 3, og gamle storage-stier migreres ikke. Deploy følger den separate fase 3-runbook. |
| **Mediehåndtering fase 4 — identitet & endeligt farvel** | Implementeret og verificeret lokalt (2026-07-22), men **ikke live i prod** (lokal — ikke deployet). Nye funktioner i `schema.sql`: `red_erstat_media_fil` (erstat bytes, behold identitet — atomisk `AND upload_status='klar'`-gate mod race), `red_udrens_media_preview`+`red_udrens_media` (permanent sletning, blokeret på SYV polymorfe ankre: relation, text_mention, fact, story, narrative, note, suggestion — guard+slet i ét atomisk `DELETE...NOT EXISTS`-statement), `red_saet_portraet` (portræt-valg, `relation.kvalifikator jsonb`-kolonne, additiv). Den scoped blok `mediehaandtering_fase4_identitet` i `db-migrations.sql` bringer en fase 3-base til samme flade (verificeret byte-identisk med `schema.sql` via SHA-256). `db-rls.sql` er uændret. Deploy følger sin egen separate, gated runbook (fase 3-præcedensen). |
| Mediehåndtering fase 5 | Dokumenttransskription er ikke designet endnu. |
| 1939-publicering | Pauset indtil nyt OCR-udtræk, nyt artefakt og fornyet komplethedsgate (uddybet i §3) |
| Import-sikkerhed | Stabil import-run/checksum/udgavenøgle og source-scoped replace mangler; `--reset` er fortsat en farlig nødvej |
| Skalering | Klienterne materialiserer hele grafen; bounded server-slices/keyset-pagination mangler |

---

## 5. Gated deployprocedure

1. **Lås scope:** navngiv prod-projekt og præcis migrationsblok/feature. Ingen bred
   "kør alt"-antagelse.
2. **Read-only preflight:** tag katalog-/tælle-snapshot og bekræft forventet baseline.
3. **Backup:** krypteret `pg_dump` af prod; opbevar PII uden for Git.
4. **Restore-rehearsal:** gendan dumpet i en lokal engangsbase, kør den identiske
   migrations-/RLS-sti, mål blast radius og øv rollback.
5. **Eksplicit godkendelse:** brugeren navngiver prod-målet og det konkrete apply.
6. **Atomisk apply:** `--single-transaction` hvor artefaktet tillader det; genanvend
   `db-rls.sql` når policies/grants påvirkes.
7. **Verificér:** scoped adfærdsasserts, read-only katalog-/RLS-smoke, Data API-grants,
   schema-cache og Supabase security advisors.
8. **Dokumentér:** opdatér changelog og denne side med faktisk resultat, tal og
   rollback-artefakt. Markér tydeligt kodeklar versus live.

Git-, app- og prod-databasestatus er tre separate dimensioner. En merge eller grøn CI
er aldrig i sig selv et prod-deploy.

---

## 6. Se også

- `docs/changelog.md` — kronologisk historik og test-/deploybeviser.
- `docs/fase4-runbook.md` — det gennemførte Problem 2/A1/K2-cutover og 1939-loadets
  tidligere runbook.
- `docs/decisions.md` — arkitekturbeslutninger.
- `datamodel-oversigt.md` — konceptuel model.
- `docs/README.md` — dokumentationsindeks.

## Mediehåndtering fase 1+2 — LIVE i prod (2026-07-20)

Redaktionslaget har nu en filside for eksisterende `media`-rækker. Kuraterbare metadata
(`titel`, `slags`, `kunstner`, `datering`) opdateres via `red_opdater_media`; blødt fjernede
rækker kan genoprettes via `red_genopret_media`. Rettighedsgaten vedligeholdes fortsat gennem
`red_set_media_rettigheder`, og `red_upload_media` accepterer nu også kunstner og datering.

`upload_status='fjernet'` er fortsat usynlig for offentligheden og for almindelige medlemmer.
Redaktionen læser derimod rækken for at kunne vise status og genoprette den. Lightbox og
narrativ-mention-pickere filtrerer eksplicit til `upload_status='klar'`.

`red_doede_links` er udvidet med `maal_type='media'`: kun et media-id uden en eksisterende
`media`-række er dødt. En række med `upload_status='fjernet'` er ikke død, fordi den stadig
findes og kan genoprettes. `security_invoker` er bevaret. Samtidig fik `text_mention` sit
hidtil manglende `GRANT SELECT` (viewet var reelt utilgængeligt for alle, inkl. redaktionen,
siden 2026-06-30) og `tm_read`-policyen bruger nu `media_synlig_anon` for `maal_type='media'`
i stedet for `entitet_offentlig`s ubetingede `true`-gren — lukker et latent fail-open-hul
(aldrig udnyttet i praksis, da manglende GRANT gjorde tabellen uforespørgelig).

Se §2 for detaljer om deploy-vejen (kørt direkte via Supabase MCP samme dag som levende
feed fase 2-3, se ovenfor).
