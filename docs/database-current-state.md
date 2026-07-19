# Database — Current State (operatør-guide)

> **Formål:** Ét sted der siger, hvad der faktisk er i prod nu, hvilke SQL-filer der
> er autoritative, og hvordan næste deploy forberedes sikkert. Changelog fortæller
> historien; denne side fortæller tilstanden.
>
> **Sidst afstemt:** 2026-07-20 mod prod `xjnvdhajfyrcytatnzos` med read-only
> katalog- og aggregatqueries samt mod `docs/changelog.md`. Der blev ikke kørt DDL,
> DML eller `red_*`-kald. Ved uenighed med ældre planer/specs gælder denne side for
> prod-status; ret derefter det forældede dokument i dets egen dokumentationsrunde.

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
- `parse_mentions`, `text_mention` og døde-links-viewet er live. Media-grenen i den
  nye fase 2-version af `red_doede_links` er **ikke** deployet endnu.
- Konto-bogmærker er live med owner-bundet RLS.

### Medier — Slice 0 live

- `media`, `media_variant`, privat Storage-bucket, afbildet-/rettighedsgating,
  upload/bekræft, variantregistrering, blødt fjern og Storage-politikker er live.
- Prod har seks media-rækker; fire er blødt fjernet og kan ikke ses offentligt.
- `red_opdater_media` og `red_genopret_media` findes **ikke** i prod. Fase 1-filsiden
  og fase 2-biblioteket er kodeklare, men deres SQL/RLS/app-deploy er fortsat gated.

---

## 4. Hvad er ikke live / bevidst udskudt

| Emne | Status |
|---|---|
| Levende feed fase 2 | `haendelse` og første prod-pipeline-load mangler |
| Levende feed fase 3 | `story`, `story_kilde`, `feed_pin` og de syv RPC'er mangler |
| Levende feed fase 4 | LLM-assist/Edge Function er ikke implementeret |
| Mediehåndtering fase 1–2 | UI/kode er merget; samlet migration, RLS, E2E og app-deploy mangler |
| Mediehåndtering fase 3–5 | Hygiejne/dedup, identitet/udrensning og dokumenttransskription er ikke implementeret |
| 1939-publicering | Pauset indtil nyt OCR-udtræk, nyt artefakt og fornyet komplethedsgate |
| Authenticated medlem/forsker | Samtykke- og slægtsscope er ikke designet/deployeret; tieret er bevidst fail-closed |
| Multi-writer | `max(id)+1` er race-følsomt; IDENTITY/sekvenser kræves før flere samtidige redaktører |
| Import-sikkerhed | Stabil import-run/checksum/udgavenøgle og source-scoped replace mangler; `--reset` er fortsat en farlig nødvej |
| Skalering | Klienterne materialiserer hele grafen; bounded server-slices/keyset-pagination mangler |
| Vocab/integritet | Flere polymorfe targets og vocab-værdier håndhæves stadig konventionelt frem for med fulde FK/CHECKs |

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
