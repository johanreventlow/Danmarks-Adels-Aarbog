# Levende feed — fase 3: minihistorier & redaktionel styring · Implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Redaktøren kan skrive korte minihistorier (`story`) forankret i hændelser og kilder,
publicere dem som feed'ens flagskibs-kort (`historie`), og styre feed'en direkte via pin/skjul
(`feed_pin`) — hvorved den døde `FeedOverride`-krog endelig realiseres og web-forsidens
startpersoner udledes af portræt-pins.

**Architecture:** Skive 1 er én additiv migration (tre tabeller + vocab + RLS + syv RPC'er +
**fuld** versionering af `story`/`feed_pin` — bevidst modsat `haendelse`s skip_cols-tunge række).
Skive 2–3 udvider den rene motor (`historie`-kort, dedup, pin-blok/skjul-filter) og
loader-spejlparrene efter hændelses-skabelonen; uden stories+pins er ordningen dybt identisk med
fase 2 (regressions-invariant). Skive 4–5 er kort-views, write-lag gennem det eksisterende
`Change`/`buildRpcCall`/dry-run-flow, inline story-editor i begge apps og en dedikeret
feed-styringsside kun på web (mobil er dev-only). Skive 6 er afstemning — ingen nye CI-jobs.

**Tech Stack:** PostgreSQL/Supabase (RLS, plpgsql, PostgREST), TypeScript + vitest
(`packages/feed`), React Native/Expo + jest (mobil), React/Vite + vitest (web).

**Kilder:**
- Spec: `docs/superpowers/specs/2026-07-19-levende-feed-fase3-design.md` (autoritativ; §-referencer nedenfor peger dertil)
- Koncept: `docs/design/2026-07-18-levende-feed-koncept.md` (§3.2–3.4 story-skema, §7 redaktionsflow, §10 fase 3)
- Fase 2-implementeringen (den faktiske kode): `packages/feed/src/`, `mobile/src/data/haendelser.ts`, `web/src/data/haendelser.ts`, `web/src/components/feed/FeedStreamView.tsx`, `mobile/src/components/redaktion/HaendelseTidslinje.tsx`, `web/src/Redaktion.tsx`
- DB-konventioner: `schema.sql`, `db-migrations.sql`, `db-rls.sql`, `db-verify.sql` (fase 2-sektionerne er de operative skabeloner)

## Global Constraints

- **Migrationen er additiv og afgrænset:** KUN `story`/`story_kilde`/`feed_pin` + vocab-seed +
  RLS + 7 RPC'er + versionering. Evidenslaget (fact/assertion/conclusion/citation/narrative) OG
  hændelseslaget (`haendelse` + pipeline) røres IKKE — ingen eksisterende tabel, politik eller
  RPC ændres (spec §9.1).
- **`story`/`feed_pin` er ægte redaktionelt indhold** (ikke regenererbare projektioner):
  fuld versionering med `skip_cols = '{}'`; `story_kilde` versioneres IKKE (erstat-semantik,
  spec §3.7). Fortryd af `red_set_story_kilder`/`red_slet_story` genskaber ikke kildelisten.
- **Ren motor:** ingen netværk/`Math.random`/`Date.now` i `packages/feed`; al ny dynamik
  injiceres (`storieBy`, `pins`, `todayISO`). `storieBy`+`pins` udeladt/tomme ⇒ ordningen er
  **dybt identisk med fase 2** (regressions-invariant, spec §4.5 — testes eksplicit, og pin-
  koden må ALDRIG forbruge ekstra `rng()`-kald).
- **Tolerant klient-load:** enhver fejl (inkl. u-migreret base) ⇒ `{}`/`[]` + `console.warn` —
  feed'en brydes aldrig; alt degraderer til fase 2-adfærd.
- **GDPR (invariant #8):** story-RLS fail-closer via `entitet_offentlig` + `privat`-flag;
  klienten filtrerer desuden defensivt. `feed_pin` bærer ingen PII og er offentligt læsbar.
- **Intet LLM i fase 3:** `oprindelse='redaktoer'` er hårdkodet i `red_opret_story` (ingen
  oprindelse-parameter); `llm_*`-kolonnerne står tomme til fase 4.
- **Prod er gated:** alt SQL verificeres mod kopi-base **med fase 2 anvendt først** (spec §2);
  `docs/database-current-state.md` opdateres først ved den reelle prod-migrering, som omfatter
  fase 2 + fase 3 i rækkefølge + gen-anvendelse af `db-rls.sql` + `get_advisors(security)`.
- **Ingen nye farver/fonte:** mobil styler fra `mobile/src/theme/tokens.ts`, web fra
  `web/src/theme.ts`.
- Hver task holder relevante suiter grønne: `packages/feed` → `npx vitest run` +
  `npx tsc --noEmit`; mobil → `npx tsc --noEmit && npm test` (fra `mobile/`); web →
  `npm run test` + `npm run build` (fra `web/`).
- Commit-beskeder på dansk, `feat(feed): …`-stil; brug din egen sessions Claude-Session-footer.

**Rækkefølge/parallelitet (spec §2):** Task 1 (skive 1) er forudsætning for task 6–7 og 9–11
(mod rigtig base). Task 2–5 (motoren) kan bygges parallelt med task 1 (netværksfri, testes mod
fixtures) men sekventielt indbyrdes (2 → 3 → 4 → 5). Task 6–7 kræver task 2–3; task 8 kræver
task 6–7; task 12 kræver task 7; task 13 sidst. Rækkefølgen nedenfor er den anbefalede serielle.

---

## Filstruktur

| Fil | Ansvar | Task |
|---|---|---|
| `schema.sql` | `story`/`story_kilde`/`feed_pin`-tabeller + 7 RPC'er + registry-rækker (loopet tilknytter triggers) | 1 |
| `db-migrations.sql` | Idempotent dateret fase 3-sektion (tabeller, vocab, RPC'er, grants, registry, eksplicitte triggers) | 1 |
| `db-rls.sql` | story/story_kilde/feed_pin-politikker + eksplicitte revokes | 1 |
| `db-verify.sql` | Fase 3-asserts: CHECK/UNIQUE/RLS-synlighed/RPC-gates/fuld-versionerings-fortryd | 1 |
| `packages/feed/src/types.ts` | `historie`-kind, `StoryItem`/`StorieBy`, `FeedPinInput`; `FeedOverride`+`overrides` SLETTES | 2 |
| `packages/feed/src/story.ts` (+ test) | `buildStorieBy` (ren join, skive 3) + `buildStorieKort` (motor, skive 2) | 2, 4 |
| `packages/feed/src/pins.ts` (+ test) | `buildFeedPins` — deterministisk pin-normalisering | 3 |
| `packages/feed/src/score.ts` | `BASE.historie = 1.2` + nyPubliceret-boost ×2 | 2, 4 |
| `packages/feed/src/pool.ts` (+ test) | `buildPortraitAndCitat` får story-dedup-parameter | 4 |
| `packages/feed/src/order.ts` (+ `order.test.ts`) | Skjul-filter, pin-blok, lås-offsets; **regressions-invarianten** | 5 |
| `packages/feed/src/index.ts` | `export * from './story'` / `'./pins'` | 2, 3 |
| `mobile/src/data/story.ts`, `feedPins.ts` (+ tests), `load.ts`, `store/useStore.ts`, `app/(tabs)/index.tsx` | Mobil-load + store-felter + strøm-input | 6 |
| `web/src/data/story.ts`, `feedPins.ts` (+ tests), `components/feed/FeedStreamView.tsx`, `components/HomeView.tsx` | Web-load + resume; pins løftes til forsiden (genbruges i task 12) | 7 |
| `mobile/src/components/feed/FeedCardView.tsx`, `web/src/components/feed/FeedCardView.tsx` | `case 'historie'` + person-navigation | 8 |
| `mobile/src/data/redaktionWrite.ts`, `web/src/data/redaktionWrite.ts` (+ tests) | 7 nye `Change`-arter → `buildRpcCall`-mapninger | 9 |
| `mobile/src/data/redaktionRead.ts`, `web/src/data/redaktionRead.ts` (+ tests), `web/src/Redaktion.tsx`, `mobile/src/components/redaktion/HaendelseTidslinje.tsx`, `mobile/src/app/redaktion/person/[id].tsx` | `mapStories` + prefill + inline story-editor | 10 |
| `web/src/components/FeedStyring.tsx` (+ test), `web/src/Redaktion.tsx`, `web/src/data/feedPins.ts`, `web/src/data/redaktionRead.ts` | Feed-styringsside (KUN web) | 11 |
| `web/src/data/home.ts` (+ test), `web/src/components/HomeView.tsx` | `forsideStartpersoner` fra portræt-pins | 12 |
| `docs/changelog.md`, `docs/README.md`, `docs/design/2026-07-18-levende-feed-koncept.md` | Afstemning; ingen CI-ændringer (spec §8) | 13 |

---

## Task 1: DB — `story` + `story_kilde` + `feed_pin` + vocab + RLS + 7 RPC'er + versionering (skive 1)

**Files:**
- Modify: `schema.sql` — de tre tabeller + vocab indsættes EFTER `haendelse`-blokkens vocab-seed
  (`schema.sql:452-466`), dvs. FØR `-- ---------- CACHE-REGENERERING & TRIGGERS ----------`
  (linje 468) — det nye formidlingslag bor ved det gamle. De 7 RPC'er indsættes EFTER
  `red_set_haendelse_status` (`schema.sql:899-913`), før `red_slet_person`-kommentaren (linje
  915). **TO NYE rækker i den EKSISTERENDE `version_pk_registry`-INSERT** (`schema.sql:1816-1840`)
  — efter `('haendelse', …)`-rækken (linje 1827): `('story', ARRAY['id'], '{}')` og
  `('feed_pin', ARRAY['id'], '{}')`. Skriv INGEN `CREATE TRIGGER` i schema.sql: filens generiske
  trigger-loop (`schema.sql:1948-1957`, `FOR r IN SELECT tabel FROM version_pk_registry LOOP …`)
  kører EFTER listen og tilknytter `trg_log_story`/`trg_log_feed_pin` selv (fase 2-planens
  verificerede asymmetri).
- Modify: `db-migrations.sql` — NY dateret sektion appendes til sidst (efter fase 2-sektionen,
  fil-slut linje 2635) med samme bannerstil:
  `-- 2026-07-19: levende feed fase 3 — story/story_kilde/feed_pin (kurateret lag, fase3-spec §3)`.
  Her er situationen OMVENDT: filens generiske loop er allerede kørt, så sektionen skal SELV
  indeholde sin `INSERT INTO version_pk_registry … ON CONFLICT (tabel) DO UPDATE` OG eksplicitte
  `CREATE TRIGGER trg_log_story`/`trg_log_feed_pin` (spejl af fase 2-sektionens linje 2626-2635)
  — PLUS `REVOKE`/`GRANT EXECUTE … TO authenticated` for alle syv RPC'er (db-migrations
  gen-anvender ikke RLS-laget; fase 4-runbook-lektien).
- Modify: `db-rls.sql` — ny sektion indsættes efter redaktion-loopet (`db-rls.sql:536-547`), før
  `FREMTID`-kommentarblokken (linje 553): story (anon/auth/redaktion_read), story_kilde
  (EXISTS-cascade + redaktion_read), feed_pin (anon/auth `using (true)`), alle med **eksplicitte
  revokes mod anon+authenticated** (review 22: `REVOKE FROM PUBLIC` er utilstrækkeligt). Det
  generiske `red\_%`-grant-loop (`db-rls.sql:513-518`) fanger alle syv RPC'er ved gen-anvendelse
  — ingen ændring dér.
- Modify: `db-verify.sql` — nyt `DO $$ … END $$;`-blok appendes efter fase 2-blokket (fil-slut
  linje 1716).

**Interfaces (spec §3.1–§3.5 er den autoritative tabel-/vocab-/RLS-SQL — kopiér ordret derfra):**
- `story` (spec §3.1): BIGINT-PK uden IDENTITY; polymorf `subjekt_type/subjekt_id`; fire
  valgfrie ankre (`haendelse_id`/`fact_id`/`relation_id`/`historical_event_id`) med
  `ON DELETE SET NULL` (redaktionelt indhold OVERLEVER sit anker — bevidst modsat
  `haendelse.narrative_id ON DELETE CASCADE`); fuzzy dato = assertion-felterne; `status` CHECK
  `('kladde','klar','publiceret','arkiveret')` DEFAULT `'kladde'`; `publiceret_dato DATE`;
  `oprindelse` CHECK `('redaktoer','llm_assisteret')` DEFAULT `'redaktoer'`;
  `llm_model`/`llm_promptversion`/`llm_naar` (forward-kompat, ubrugte); `skabt_af UUID NOT NULL
  DEFAULT auth.uid()`; `godkendt_af`/`godkendt_naar`; `privat BOOLEAN NOT NULL DEFAULT false`;
  indexes `ix_story_subjekt`/`ix_story_haendelse`/`ix_story_status`.
- `story_kilde` (spec §3.2): `story_id … ON DELETE CASCADE`, `source_id … REFERENCES source(id)`,
  `side TEXT`; `ix_story_kilde_story`.
- `feed_pin` (spec §3.3): `kort_noegle TEXT NOT NULL UNIQUE` (pin OG skjul kan aldrig
  sameksistere), `handling` CHECK `('pin','skjul')`, `oprettet_af UUID NOT NULL DEFAULT
  auth.uid()`, `oprettet_naar TIMESTAMPTZ NOT NULL DEFAULT now()`. Ingen ny vocab-scheme for
  handling (to koder, lukket sæt — som `person.koen`).
- Vocab (spec §3.4): `story_status` (4 koder) + `story_oprindelse` (2 koder),
  `ON CONFLICT (scheme, code) DO NOTHING`.
- RLS (spec §3.5): story anon/auth = `status = 'publiceret' AND coalesce(privat,false) = false
  AND entitet_offentlig(subjekt_type, subjekt_id)`; redaktion_read =
  `(select current_rolle()) = 'redaktion'`; story_kilde = `exists(select 1 from public.story s
  where s.id = story_id)` (note→fact-mønstret) + egen redaktion_read; feed_pin anon/auth
  `using (true)`.
- **De 7 RPC'er (spec §3.6) — fuld SQL i Step 3 nedenfor.** Alle: gate på
  `current_rolle() = 'redaktion'` → validér → `PERFORM begin_change_set(…)` → skriv; id'er via
  basens `(SELECT coalesce(max(id),0)+1 FROM …)`-mønster (`schema.sql:620` note + fx linje 644).
  Dermed er dry-run/LIVE og fortryd gratis via det eksisterende `submitChange`-flow.
- Versionering (spec §3.7): `('story', ARRAY['id'], '{}')` + `('feed_pin', ARRAY['id'], '{}')`
  — INGEN skip_cols (fuldversionering er hele pointen; DELETE-fortryd genskaber hele rækken).
  `story_kilde` holdes UDE af registry.

- [ ] **Step 1: Skriv de fejlende asserts (RED).** Appendér nedenstående blok til
  `db-verify.sql` (negative sentinel-id'er i det ubrugte bånd `-987657xxx` — fase 2 bruger
  `-987656xxx`, K2 `-987655xxx`; `story.skabt_af`/`feed_pin.oprettet_af` har `DEFAULT auth.uid()`
  som er NULL for basens ejer, derfor sættes en sentinel-uuid eksplicit i seeds):

```sql
-- ===== Levende feed fase 3: story/story_kilde/feed_pin — skema, RLS, RPC'er og fortryd =====
DO $$
DECLARE
  v_pub int; v_kladde int; v_levende int; v_privat int;
  v_kilde int; v_kilde_kladde int; v_pin int; v_auth_pub int; v_auth_kladde int;
  v_uid uuid := '00000000-0000-0000-0000-0000000000f3';
  v_seed_af uuid := '00000000-0000-0000-0000-0000000000f4';
  v_story bigint; v_cs_opret bigint; v_cs_status bigint;
  v_undo1 bigint; v_undo2 bigint; v_res jsonb;
BEGIN
  IF to_regclass('public.story') IS NULL THEN RAISE EXCEPTION 'Fase3: story-tabellen mangler'; END IF;
  IF to_regclass('public.story_kilde') IS NULL THEN RAISE EXCEPTION 'Fase3: story_kilde mangler'; END IF;
  IF to_regclass('public.feed_pin') IS NULL THEN RAISE EXCEPTION 'Fase3: feed_pin mangler'; END IF;
  IF NOT EXISTS (SELECT 1 FROM version_pk_registry WHERE tabel='story' AND skip_cols='{}') THEN
    RAISE EXCEPTION 'Fase3: story mangler i version_pk_registry uden skip_cols (fuld versionering, §3.7)';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM version_pk_registry WHERE tabel='feed_pin' AND skip_cols='{}') THEN
    RAISE EXCEPTION 'Fase3: feed_pin mangler i version_pk_registry uden skip_cols';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.story'::regclass
                 AND tgname='trg_log_story' AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'Fase3: trg_log_story mangler';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgrelid='public.feed_pin'::regclass
                 AND tgname='trg_log_feed_pin' AND NOT tgisinternal) THEN
    RAISE EXCEPTION 'Fase3: trg_log_feed_pin mangler';
  END IF;

  -- Oprydning + seeds
  DELETE FROM feed_pin WHERE kort_noegle LIKE 'verify3:%';
  DELETE FROM story_kilde WHERE id BETWEEN -987657029 AND -987657020;
  DELETE FROM story WHERE id BETWEEN -987657019 AND -987657010;
  DELETE FROM source WHERE id=-987657031;
  DELETE FROM person WHERE id IN (-987657001,-987657002);
  INSERT INTO person(id,levende,privat,staged) VALUES
    (-987657001,true,false,false),(-987657002,false,false,false);
  INSERT INTO source(id,titel,udgave) VALUES (-987657031,'Verify-kilde','1939');
  INSERT INTO story(id,subjekt_type,subjekt_id,tekst,status,privat,skabt_af) VALUES
    (-987657011,'person',-987657002,'Publiceret offentlig historie','publiceret',false,v_seed_af),
    (-987657012,'person',-987657002,'Kladde-historie','kladde',false,v_seed_af),
    (-987657013,'person',-987657001,'Publiceret om levende','publiceret',false,v_seed_af),
    (-987657014,'person',-987657002,'Publiceret men privat','publiceret',true,v_seed_af);
  INSERT INTO story_kilde(id,story_id,source_id,side) VALUES
    (-987657021,-987657011,-987657031,'112'),
    (-987657022,-987657012,-987657031,'7');
  INSERT INTO feed_pin(id,kort_noegle,handling,oprettet_af) VALUES
    (-987657041,'verify3:portrait:1','pin',v_seed_af);

  -- CHECK + UNIQUE
  BEGIN
    INSERT INTO story(id,subjekt_type,subjekt_id,tekst,status,skabt_af)
      VALUES (-987657015,'person',-987657002,'X','udgivet',v_seed_af);
    RAISE EXCEPTION 'Fase3: story.status-CHECK fyrede ikke';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO story(id,subjekt_type,subjekt_id,tekst,oprindelse,skabt_af)
      VALUES (-987657015,'person',-987657002,'X','ai',v_seed_af);
    RAISE EXCEPTION 'Fase3: story.oprindelse-CHECK fyrede ikke';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO feed_pin(id,kort_noegle,handling,oprettet_af)
      VALUES (-987657042,'verify3:x','fremhaev',v_seed_af);
    RAISE EXCEPTION 'Fase3: feed_pin.handling-CHECK fyrede ikke';
  EXCEPTION WHEN check_violation THEN NULL; END;
  BEGIN
    INSERT INTO feed_pin(id,kort_noegle,handling,oprettet_af)
      VALUES (-987657043,'verify3:portrait:1','skjul',v_seed_af);
    RAISE EXCEPTION 'Fase3: feed_pin UNIQUE(kort_noegle) fyrede ikke';
  EXCEPTION WHEN unique_violation THEN NULL; END;

  -- RLS-synlighed (anon + authenticated, F-02-linjen)
  SET LOCAL ROLE anon;
  SELECT count(*) INTO v_pub     FROM story WHERE id=-987657011;
  SELECT count(*) INTO v_kladde  FROM story WHERE id=-987657012;
  SELECT count(*) INTO v_levende FROM story WHERE id=-987657013;
  SELECT count(*) INTO v_privat  FROM story WHERE id=-987657014;
  SELECT count(*) INTO v_kilde        FROM story_kilde WHERE id=-987657021;
  SELECT count(*) INTO v_kilde_kladde FROM story_kilde WHERE id=-987657022;
  SELECT count(*) INTO v_pin FROM feed_pin WHERE kort_noegle='verify3:portrait:1';
  RESET ROLE;
  SET LOCAL ROLE authenticated;
  SELECT count(*) INTO v_auth_pub    FROM story WHERE id=-987657011;
  SELECT count(*) INTO v_auth_kladde FROM story WHERE id=-987657012;
  RESET ROLE;
  IF v_pub<>1 OR v_kladde<>0 OR v_levende<>0 OR v_privat<>0
     OR v_kilde<>1 OR v_kilde_kladde<>0 OR v_pin<>1
     OR v_auth_pub<>1 OR v_auth_kladde<>0 THEN
    RAISE EXCEPTION 'Fase3 RLS FEJL pub=% kladde=% levende=% privat=% kilde=% kilde_kladde=% pin=% auth_pub=% auth_kladde=%',
      v_pub,v_kladde,v_levende,v_privat,v_kilde,v_kilde_kladde,v_pin,v_auth_pub,v_auth_kladde;
  END IF;

  -- RPC-gates
  PERFORM set_config('request.jwt.claim.sub','',true);
  BEGIN
    PERFORM red_opret_story('person',-987657002,'Uautoriseret');
    RAISE EXCEPTION 'Fase3: red_opret_story afviste ikke ikke-redaktør';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE 'Kun redaktion%' THEN RAISE; END IF; END;
  BEGIN
    PERFORM red_set_feed_pin('verify3:portrait:1','pin');
    RAISE EXCEPTION 'Fase3: red_set_feed_pin afviste ikke ikke-redaktør';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE 'Kun redaktion%' THEN RAISE; END IF; END;

  INSERT INTO auth.users(id,email) VALUES (v_uid,'fase3@test.invalid') ON CONFLICT (id) DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES (v_uid,'redaktion','fase3@test.invalid')
    ON CONFLICT (id) DO UPDATE SET rolle='redaktion';
  PERFORM set_config('request.jwt.claim.sub',v_uid::text,true);
  BEGIN
    PERFORM red_set_story_status(-987657011,'udgivet');
    RAISE EXCEPTION 'Fase3: ugyldig story-status blev ikke afvist';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE '%ikke en gyldig story-status%' THEN RAISE; END IF; END;
  BEGIN
    PERFORM red_set_feed_pin('verify3:x','fremhaev');
    RAISE EXCEPTION 'Fase3: ugyldig pin-handling blev ikke afvist';
  EXCEPTION WHEN others THEN IF SQLERRM NOT LIKE '%ikke en gyldig pin-handling%' THEN RAISE; END IF; END;

  -- Fortryd-assert (fuld versionering, §3.7/§3.8): begge retninger
  v_story := red_opret_story('person',-987657002,'Fortryd-testhistorie','Titel');
  v_cs_opret := current_setting('app.change_set_id')::bigint;
  PERFORM set_config('app.change_set_id','',true);
  PERFORM red_set_story_status(v_story,'publiceret');
  v_cs_status := current_setting('app.change_set_id')::bigint;
  IF (SELECT status FROM story WHERE id=v_story) <> 'publiceret'
     OR (SELECT publiceret_dato FROM story WHERE id=v_story) IS NULL THEN
    RAISE EXCEPTION 'Fase3: publicering satte ikke status/publiceret_dato';
  END IF;
  PERFORM set_config('app.change_set_id','',true);
  v_res := red_fortryd_change_set(v_cs_status,false);
  v_undo1 := (v_res->>'reversal_change_set')::bigint;
  IF (SELECT status FROM story WHERE id=v_story) <> 'kladde' THEN
    RAISE EXCEPTION 'Fase3: fortryd af status-skiftet genskabte ikke kladde';
  END IF;
  PERFORM set_config('app.change_set_id','',true);
  v_res := red_fortryd_change_set(v_cs_opret,false);
  v_undo2 := (v_res->>'reversal_change_set')::bigint;
  IF EXISTS (SELECT 1 FROM story WHERE id=v_story) THEN
    RAISE EXCEPTION 'Fase3: fortryd af opret-settet slettede ikke storyen';
  END IF;

  -- Oprydning
  PERFORM set_config('app.change_set_id','',true);
  DELETE FROM feed_pin WHERE kort_noegle LIKE 'verify3:%';
  DELETE FROM story_kilde WHERE id BETWEEN -987657029 AND -987657020;
  DELETE FROM story WHERE id BETWEEN -987657019 AND -987657010;
  DELETE FROM source WHERE id=-987657031;
  DELETE FROM person WHERE id IN (-987657001,-987657002);
  DELETE FROM change_event WHERE change_set_id IN (v_cs_opret,v_cs_status,v_undo1,v_undo2);
  DELETE FROM change_set WHERE id IN (v_undo1,v_undo2,v_cs_status,v_cs_opret);
  DELETE FROM profiles WHERE id=v_uid;
  DELETE FROM auth.users WHERE id=v_uid;
  PERFORM set_config('request.jwt.claim.sub','',true);
  RAISE NOTICE 'OK: levende feed fase 3 (story/story_kilde/feed_pin CHECK/UNIQUE/RLS/RPC/fuld versionering/fortryd)';
END $$;
```

- [ ] **Step 2: Kør blokket mod kopi-basen (med fase 2 anvendt, MEN uden fase 3) — verificér
  FAIL:** `psql "$KOPI_BASE_URL" -f db-verify.sql` → forventet:
  `ERROR: Fase3: story-tabellen mangler` (fejler allerede på `to_regclass`).
- [ ] **Step 3: Implementér** SQL'en i alle fire filer jf. Files/Interfaces (tabeller/vocab/RLS:
  spec §3.1–§3.5 ordret; kommentarstil som naboblokkene — dansk, med invariant-referencer).
  De syv RPC'er skrives sådan (i BÅDE `schema.sql` og migrationssektionen — identisk tekst;
  grants/revokes KUN i migrationen, `db-rls.sql`-loopet dækker gen-anvendelse):

```sql
-- Redaktionelle minihistorier + feed-kurering (fase3-spec §3.6): eneste skrivevej.
-- Alle syv følger red_set_haendelse_status-skelettet: rolle-gate → validér →
-- begin_change_set → skriv (dry-run/LIVE + fortryd gratis via det eksisterende flow).
CREATE OR REPLACE FUNCTION red_opret_story(
  p_subjekt_type text, p_subjekt_id bigint, p_tekst text,
  p_titel text DEFAULT NULL, p_haendelse_id bigint DEFAULT NULL,
  p_fact_id bigint DEFAULT NULL, p_relation_id bigint DEFAULT NULL,
  p_historical_event_id bigint DEFAULT NULL,
  p_date_min date DEFAULT NULL, p_date_max date DEFAULT NULL,
  p_date_qualifier text DEFAULT NULL, p_date_raw text DEFAULT NULL,
  p_privat boolean DEFAULT false)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF p_tekst IS NULL OR btrim(p_tekst) = '' THEN RAISE EXCEPTION 'Story-tekst må ikke være tom'; END IF;
  PERFORM begin_change_set('red_opret_story',
    format('Oprettede story om %s %s', p_subjekt_type, p_subjekt_id), p_subjekt_type, p_subjekt_id);
  -- oprindelse='redaktoer' via kolonne-DEFAULT — RPC'en tager INGEN oprindelse-parameter (fase 3-hegn).
  INSERT INTO story (id, subjekt_type, subjekt_id, haendelse_id, fact_id, relation_id,
                     historical_event_id, titel, tekst, date_min, date_max, date_qualifier,
                     date_raw, privat)
  VALUES ((SELECT coalesce(max(id),0)+1 FROM story), p_subjekt_type, p_subjekt_id,
          p_haendelse_id, p_fact_id, p_relation_id, p_historical_event_id,
          p_titel, p_tekst, p_date_min, p_date_max, p_date_qualifier, p_date_raw, p_privat)
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION red_rediger_story(
  p_story_id bigint, p_tekst text,
  p_titel text DEFAULT NULL, p_haendelse_id bigint DEFAULT NULL,
  p_fact_id bigint DEFAULT NULL, p_relation_id bigint DEFAULT NULL,
  p_historical_event_id bigint DEFAULT NULL,
  p_date_min date DEFAULT NULL, p_date_max date DEFAULT NULL,
  p_date_qualifier text DEFAULT NULL, p_date_raw text DEFAULT NULL,
  p_privat boolean DEFAULT false)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_stype text; v_sid bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF p_tekst IS NULL OR btrim(p_tekst) = '' THEN RAISE EXCEPTION 'Story-tekst må ikke være tom'; END IF;
  SELECT subjekt_type, subjekt_id INTO v_stype, v_sid FROM story WHERE id=p_story_id;
  IF v_stype IS NULL THEN RAISE EXCEPTION 'Story % findes ikke', p_story_id; END IF;
  PERFORM begin_change_set('red_rediger_story',
    format('Redigerede story %s', p_story_id), v_stype, v_sid);
  -- Erstat-semantik: editoren sender ALTID hele den aktuelle tilstand (deterministisk,
  -- komplet dry-run-preview). status/publiceret_dato røres IKKE (kun red_set_story_status).
  UPDATE story SET titel=p_titel, tekst=p_tekst, haendelse_id=p_haendelse_id,
    fact_id=p_fact_id, relation_id=p_relation_id, historical_event_id=p_historical_event_id,
    date_min=p_date_min, date_max=p_date_max, date_qualifier=p_date_qualifier,
    date_raw=p_date_raw, privat=p_privat
  WHERE id=p_story_id;
END $$;

CREATE OR REPLACE FUNCTION red_set_story_status(p_story_id bigint, p_status text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_stype text; v_sid bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF p_status NOT IN ('kladde','klar','publiceret','arkiveret') THEN
    RAISE EXCEPTION '''%'' er ikke en gyldig story-status (kladde|klar|publiceret|arkiveret)', p_status;
  END IF;
  SELECT subjekt_type, subjekt_id INTO v_stype, v_sid FROM story WHERE id = p_story_id;
  IF v_stype IS NULL THEN RAISE EXCEPTION 'Story % findes ikke', p_story_id; END IF;
  PERFORM begin_change_set('red_set_story_status',
    format('Satte status %s på story %s', p_status, p_story_id), v_stype, v_sid);
  -- Hver overgang TIL 'publiceret' sætter publiceret_dato; overgange VÆK rører den ikke
  -- (historisk dato bevares — klienten viser alligevel kun status='publiceret', §3.6).
  UPDATE story SET status = p_status,
    publiceret_dato = CASE WHEN p_status = 'publiceret' THEN current_date ELSE publiceret_dato END
  WHERE id = p_story_id;
END $$;

CREATE OR REPLACE FUNCTION red_slet_story(p_story_id bigint)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_stype text; v_sid bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  SELECT subjekt_type, subjekt_id INTO v_stype, v_sid FROM story WHERE id=p_story_id;
  IF v_stype IS NULL THEN RAISE EXCEPTION 'Story % findes ikke', p_story_id; END IF;
  PERFORM begin_change_set('red_slet_story',
    format('Slettede story %s (hård slet — fejloprettelse)', p_story_id), v_stype, v_sid);
  -- HÅRD slet, forbeholdt fejloprettelser (normal vej = status 'arkiveret'). Forsvarlig
  -- fordi story fuldversioneres: DELETE-eventet bærer hele rækken, fortryd genskaber den.
  -- story_kilde-rækkerne cascader og genskabes IKKE af fortryd (versioneres ikke, §3.7)
  -- — de gen-sættes via red_set_story_kilder.
  DELETE FROM story WHERE id=p_story_id;
END $$;

CREATE OR REPLACE FUNCTION red_set_story_kilder(p_story_id bigint, p_kilder jsonb)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_stype text; v_sid bigint; v_k jsonb; v_next bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF p_kilder IS NULL OR jsonb_typeof(p_kilder) <> 'array' THEN
    RAISE EXCEPTION 'p_kilder skal være et jsonb-array af {source_id, side?}';
  END IF;
  SELECT subjekt_type, subjekt_id INTO v_stype, v_sid FROM story WHERE id=p_story_id;
  IF v_stype IS NULL THEN RAISE EXCEPTION 'Story % findes ikke', p_story_id; END IF;
  PERFORM begin_change_set('red_set_story_kilder',
    format('Satte kildeliste på story %s', p_story_id), v_stype, v_sid);
  -- Erstat-semantik (DELETE + INSERT) — kildelisten er et vedhæng uden selvstændigt liv (§3.2).
  DELETE FROM story_kilde WHERE story_id = p_story_id;
  SELECT coalesce(max(id),0) INTO v_next FROM story_kilde;
  FOR v_k IN SELECT * FROM jsonb_array_elements(p_kilder) LOOP
    IF v_k->>'source_id' IS NULL
       OR NOT EXISTS (SELECT 1 FROM source WHERE id = (v_k->>'source_id')::bigint) THEN
      RAISE EXCEPTION 'Source % findes ikke', v_k->>'source_id';
    END IF;
    v_next := v_next + 1;
    INSERT INTO story_kilde (id, story_id, source_id, side)
    VALUES (v_next, p_story_id, (v_k->>'source_id')::bigint, v_k->>'side');
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION red_set_feed_pin(p_kort_noegle text, p_handling text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF p_handling NOT IN ('pin','skjul') THEN
    RAISE EXCEPTION '''%'' er ikke en gyldig pin-handling (pin|skjul)', p_handling;
  END IF;
  IF p_kort_noegle IS NULL OR btrim(p_kort_noegle) = '' THEN
    RAISE EXCEPTION 'kort_noegle må ikke være tom';
  END IF;
  -- Nøglens FORMAT valideres bevidst ikke: en nøgle uden modsvarende kort er blot en
  -- dinglende, inaktiv afgørelse — motoren ignorerer den tavst (fase3-spec §4.4).
  PERFORM begin_change_set('red_set_feed_pin',
    format('Satte %s på kort %s', p_handling, p_kort_noegle), NULL, NULL);
  INSERT INTO feed_pin (id, kort_noegle, handling)
  VALUES ((SELECT coalesce(max(id),0)+1 FROM feed_pin), p_kort_noegle, p_handling)
  ON CONFLICT (kort_noegle) DO UPDATE
    SET handling = excluded.handling, oprettet_af = auth.uid(), oprettet_naar = now();
END $$;

CREATE OR REPLACE FUNCTION red_fjern_feed_pin(p_kort_noegle text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF NOT EXISTS (SELECT 1 FROM feed_pin WHERE kort_noegle = p_kort_noegle) THEN
    RAISE EXCEPTION 'Ingen pin/skjul på %', p_kort_noegle;
  END IF;
  PERFORM begin_change_set('red_fjern_feed_pin',
    format('Fjernede kurering af kort %s', p_kort_noegle), NULL, NULL);
  DELETE FROM feed_pin WHERE kort_noegle = p_kort_noegle;
END $$;
```

  Migrationssektionens grants (spejler fase 2-sektionens `REVOKE`/`GRANT`-par, kompakt loop):

```sql
DO $$
DECLARE fn text;
BEGIN
  FOREACH fn IN ARRAY ARRAY[
    'red_opret_story(text,bigint,text,text,bigint,bigint,bigint,bigint,date,date,text,text,boolean)',
    'red_rediger_story(bigint,text,text,bigint,bigint,bigint,bigint,date,date,text,text,boolean)',
    'red_set_story_status(bigint,text)', 'red_slet_story(bigint)',
    'red_set_story_kilder(bigint,jsonb)', 'red_set_feed_pin(text,text)', 'red_fjern_feed_pin(text)']
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon;', fn);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated;', fn);
  END LOOP;
END $$;

INSERT INTO version_pk_registry (tabel, pk_cols, skip_cols) VALUES
  ('story',    ARRAY['id'], ARRAY[]::text[]),
  ('feed_pin', ARRAY['id'], ARRAY[]::text[])
ON CONFLICT (tabel) DO UPDATE SET pk_cols=excluded.pk_cols, skip_cols=excluded.skip_cols;

DROP TRIGGER IF EXISTS trg_log_story ON story;
CREATE TRIGGER trg_log_story AFTER INSERT OR UPDATE OR DELETE ON story
  FOR EACH ROW EXECUTE FUNCTION log_change();
DROP TRIGGER IF EXISTS trg_log_feed_pin ON feed_pin;
CREATE TRIGGER trg_log_feed_pin AFTER INSERT OR UPDATE OR DELETE ON feed_pin
  FOR EACH ROW EXECUTE FUNCTION log_change();
```

  `db-rls.sql`-sektionens story_kilde/feed_pin-blokke (story-blokken står ordret i spec §3.5):

```sql
-- story_kilde: arver parent-storyens synlighed (EXISTS-cascade — note→fact-mønstret).
grant select on table public.story_kilde to anon, authenticated;
revoke insert, update, delete, references, trigger, truncate on table public.story_kilde from anon, authenticated;
alter table public.story_kilde enable row level security;
drop policy if exists anon_read on public.story_kilde;
create policy anon_read on public.story_kilde for select to anon
  using (exists (select 1 from public.story s where s.id = story_id));
drop policy if exists auth_read on public.story_kilde;
create policy auth_read on public.story_kilde for select to authenticated
  using (exists (select 1 from public.story s where s.id = story_id));
drop policy if exists redaktion_read on public.story_kilde;
create policy redaktion_read on public.story_kilde for select to authenticated
  using ((select public.current_rolle()) = 'redaktion');

-- feed_pin: LÆSBAR for alle — pin/skjul-effekten skal nå klient-motoren, og en pin er
-- ren kurering uden PII (fase3-spec §3.5). Skrivning KUN via redaktions-RPC'erne.
grant select on table public.feed_pin to anon, authenticated;
revoke insert, update, delete, references, trigger, truncate on table public.feed_pin from anon, authenticated;
alter table public.feed_pin enable row level security;
drop policy if exists anon_read on public.feed_pin;
create policy anon_read on public.feed_pin for select to anon using (true);
drop policy if exists auth_read on public.feed_pin;
create policy auth_read on public.feed_pin for select to authenticated using (true);
```

- [ ] **Step 4: Kør — verificér PASS mod BEGGE deploy-stier:** (a) `schema.sql` mod en helt
  frisk kopi-base (clean-slate) — bekræft at `story`/`feed_pin` står i `version_pk_registry`
  OG at triggerne findes uden nogen trigger-kode i schema.sql:
  `SELECT tgname FROM pg_trigger WHERE tgrelid='story'::regclass AND NOT tgisinternal;`
  (forvent `trg_log_story`); (b) `db-migrations.sql` mod en kopi-base på fase 2-niveau, kørt
  **to gange** (idempotens: anden kørsel = no-op, ingen fejl); derefter `db-rls.sql`
  (gen-anvendelse — bekræft at `red\_%`-loopet fanger alle syv:
  `SELECT proname FROM pg_proc WHERE proname LIKE 'red\_%story%' ESCAPE '\';`), derefter hele
  `db-verify.sql` grøn mod migrations-stien (forvent
  `NOTICE: OK: levende feed fase 3 …` OG at fase 2-blokket stadig er grønt). Kør til sidst
  `get_advisors(security)` mod kopi-basen (etableret disciplin efter enhver DDL) — ingen nye fund.
- [ ] **Step 5: Commit** — `feat(feed): story/story_kilde/feed_pin — skema, RLS, 7 RPC'er + fuld versionering (skive 1)`.

---

## Task 2: `@daa/feed` — typer + `buildStorieBy` (skive 3, ren join)

**Files:**
- Create: `packages/feed/src/story.ts`, `packages/feed/src/__tests__/story.test.ts`.
- Modify: `packages/feed/src/types.ts` (ny `historie`-variant i `FeedCard`-unionen efter
  `arkiv`-varianten, linje 40-42; `StoryItem`/`StorieBy`/`FeedPinInput` ved siden af
  `HaendelseItem`/`HaendelserBy`, linje 24-34; `FeedInputs` linje 63-73: nye felter
  `storieBy?`/`pins?`, og `overrides?: FeedOverride[]` + `export type FeedOverride` (linje
  61+72) SLETTES — verificeret ulæst: `grep -rn "FeedOverride\|overrides" packages/feed/src
  web/src mobile/src` rammer KUN types.ts:61+72), `packages/feed/src/score.ts` (`historie: 1.2,`
  i `BASE`-recorden, linje 4-17 — obligatorisk for at kompilere: `Record<FeedCard['kind'],
  number>`), `packages/feed/src/index.ts` (nyt `export * from './story';`).

**Interfaces (spec §4.1 + §5.1 — navnene her er de autoritative og staves ens i alle senere tasks):**

```ts
// types.ts — tilføjelser:
export interface StoryItem {
  id: string;                    // story.id som streng ('story:'+id er kort-id'et)
  titel: string | null;
  tekst: string;
  dato: FuzzyDato;
  dateRaw: string | null;
  haendelseId: string | null;    // dedup-ankeret (fase3-spec §4.3)
  publiceretDato: string | null; // driver nyPubliceret-flaget i buildStorieKort
  kilde: string | null;          // 'DAA 1939, s. 112' — flere kilder joinet med ' · '
}
export type StorieBy = Record<string, StoryItem[]>;
export type FeedPinInput = { kortNoegle: string; handling: 'pin' | 'skjul' };

// FeedCard-unionen — ny variant (feltform som 'arkiv'):
| { kind: 'historie'; id: string; personId: string; titel: string | null; tekst: string;
    aarLabel: string | null; kategori: string | null; kilde: string | null;
    nyPubliceret?: boolean; kicker: string }

// FeedInputs — erstat `overrides?: FeedOverride[]` med:
  storieBy?: StorieBy;   // udeladt ⇒ fase 2-adfærd (som haendelserBy/livsdatoBy)
  pins?: FeedPinInput[]; // normaliseret, KLIENT-sorteret (§4.4) — erstatter overrides
```

- `story.ts` (ren join, spejler `buildHaendelserBy`-kontrakten i `haendelser.ts`): rå rækketyper
  `StoryRow`/`StoryKildeRow`/`StorySourceRow` (PostgREST-form, `string | number`-id'er) +
  `buildStorieBy(rows, kilder, sources, canonicalIdById = {}): StorieBy`. Kanonisering via
  `canonicalIdById[String(subjekt_id)] ?? String(subjekt_id)`; kilde-streng pr. kilde
  `'DAA <udgave>, s. <side>'` (source uden udgave ⇒ kilden udelades; ingen kilder ⇒ `null`),
  flere kilder joines i kilde-rækkernes id-orden med `' · '`; defensivt filter
  (`status !== 'publiceret'` og `privat === true` springes over); sortering pr. person på
  numerisk id.

- [ ] **Step 1: Skriv de fejlende tests** — `packages/feed/src/__tests__/story.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { buildStorieBy } from '../story';
import type { StoryRow } from '../story';

function row(id: number, over: Partial<StoryRow> = {}): StoryRow {
  return {
    id, subjekt_id: 'p1', haendelse_id: null, titel: null,
    tekst: `Historie ${id}`, date_min: null, date_max: null,
    date_qualifier: null, date_raw: null, status: 'publiceret',
    publiceret_dato: '2026-07-01', privat: false, ...over,
  };
}

describe('buildStorieBy', () => {
  it('joiner kilder/sources, kanoniserer og bevarer hændelses-ankeret', () => {
    const out = buildStorieBy(
      [row(1, { subjekt_id: 'alias', haendelse_id: 55, titel: 'Slaget' })],
      [{ id: 100, story_id: 1, source_id: 20, side: '112' }],
      [{ id: 20, udgave: '1939' }],
      { alias: 'kanonisk' },
    );
    expect(out.kanonisk).toEqual([expect.objectContaining({
      id: '1', titel: 'Slaget', haendelseId: '55',
      publiceretDato: '2026-07-01', kilde: 'DAA 1939, s. 112',
    })]);
  });

  it('joiner flere kilder deterministisk i kilde-rækkernes id-orden med " · "', () => {
    const out = buildStorieBy(
      [row(1)],
      [
        { id: 102, story_id: 1, source_id: 21, side: null },
        { id: 101, story_id: 1, source_id: 20, side: '7' },
      ],
      [{ id: 20, udgave: '1939' }, { id: 21, udgave: '2018-20' }],
    );
    expect(out.p1[0].kilde).toBe('DAA 1939, s. 7 · DAA 2018-20');
  });

  it('ingen kilder ⇒ kilde null; source uden udgave udelades', () => {
    const out = buildStorieBy(
      [row(1), row(2)],
      [{ id: 100, story_id: 2, source_id: 20, side: '5' }],
      [{ id: 20, udgave: null }],
    );
    expect(out.p1.find((s) => s.id === '1')?.kilde).toBeNull();
    expect(out.p1.find((s) => s.id === '2')?.kilde).toBeNull();
  });

  it('filtrerer defensivt ikke-publiceret og privat (defense-in-depth)', () => {
    const out = buildStorieBy([
      row(1, { status: 'kladde' }), row(2, { privat: true }), row(3),
    ], [], []);
    expect(out.p1.map((s) => s.id)).toEqual(['3']);
  });

  it('sorterer stabilt på numerisk id og håndterer tomme input', () => {
    const out = buildStorieBy([row(10), row(2)], [], []);
    expect(out.p1.map((s) => s.id)).toEqual(['2', '10']);
    expect(buildStorieBy([], [], [])).toEqual({});
  });
});
```

- [ ] **Step 2: Kør — verificér FAIL:** `npx vitest run` fra `packages/feed/` → forventet
  `Cannot find module '../story'` (eller tilsvarende resolve-fejl).
- [ ] **Step 3: Implementér** `story.ts` + types-/score-/index-ændringerne:

```ts
// packages/feed/src/story.ts
// Publicerede minihistorier (fase3-design.md §5.1): ren join af PostgREST-rækker →
// kanoniseret StorieBy. Intet netværk i pakken (spejler buildHaendelserBy).
import type { StorieBy, StoryItem } from './types';

export interface StoryRow {
  id: string | number; subjekt_id: string | number;
  haendelse_id: string | number | null;
  titel: string | null; tekst: string;
  date_min: string | null; date_max: string | null;
  date_qualifier: string | null; date_raw: string | null;
  status: string; publiceret_dato: string | null; privat: boolean | null;
}
export interface StoryKildeRow  { id: string | number; story_id: string | number;
                                  source_id: string | number; side: string | number | null; }
export interface StorySourceRow { id: string | number; udgave: string | number | null; }

export function buildStorieBy(
  rows: StoryRow[],
  kilder: StoryKildeRow[],
  sources: StorySourceRow[],
  canonicalIdById: Record<string, string> = {},
): StorieBy {
  const sourceById = new Map(sources.map((s) => [String(s.id), s]));
  const kilderByStory = new Map<string, StoryKildeRow[]>();
  for (const k of [...kilder].sort((a, b) => Number(a.id) - Number(b.id))) {
    const key = String(k.story_id);
    const list = kilderByStory.get(key);
    if (list) list.push(k); else kilderByStory.set(key, [k]);
  }
  const out: StorieBy = {};
  for (const row of rows) {
    // Defense-in-depth (koncept §9.2): RLS + query filtrerer allerede, klienten gentager.
    if (row.status !== 'publiceret' || row.privat === true) continue;
    const personId = canonicalIdById[String(row.subjekt_id)] ?? String(row.subjekt_id);
    const dele: string[] = [];
    for (const k of kilderByStory.get(String(row.id)) ?? []) {
      const source = sourceById.get(String(k.source_id));
      if (source?.udgave == null) continue; // source uden udgave ⇒ kilden udelades
      const side = k.side == null ? null : String(k.side);
      dele.push(`DAA ${String(source.udgave)}${side == null ? '' : `, s. ${side}`}`);
    }
    const item: StoryItem = {
      id: String(row.id),
      titel: row.titel,
      tekst: row.tekst,
      dato: { min: row.date_min, max: row.date_max, qualifier: row.date_qualifier },
      dateRaw: row.date_raw,
      haendelseId: row.haendelse_id == null ? null : String(row.haendelse_id),
      publiceretDato: row.publiceret_dato,
      kilde: dele.length > 0 ? dele.join(' · ') : null,
    };
    (out[personId] ??= []).push(item);
  }
  for (const items of Object.values(out)) {
    items.sort((a, b) => Number(a.id) - Number(b.id) || a.id.localeCompare(b.id));
  }
  return out;
}
```

- [ ] **Step 4: Kør — verificér PASS** + `npx tsc --noEmit` grøn i pakken (BASE-recorden har nu
  `historie: 1.2` — udeladelse ville være en tsc-fejl); mobil `tsc` + web `build` fortsat grønne
  (overrides-sletningen er verificeret ikke-brydende).
- [ ] **Step 5: Commit** — `feat(feed): buildStorieBy + historie-typer, FeedOverride udgår (skive 3)`.

---

## Task 3: `@daa/feed` — `buildFeedPins` (skive 3, pin-normalisering)

**Files:**
- Create: `packages/feed/src/pins.ts`, `packages/feed/src/__tests__/pins.test.ts`.
- Modify: `packages/feed/src/index.ts` (nyt `export * from './pins';`).

**Interfaces (spec §5.1):** `FeedPinRow { kort_noegle: string; handling: string; oprettet_naar:
string | null }` + `buildFeedPins(rows: FeedPinRow[]): FeedPinInput[]` — filtrerer ukendte
handlinger defensivt, sorterer deterministisk på `oprettet_naar` stigende (NULL sidst) med
`kort_noegle` som tiebreak. Det er hele "klienten sorterer, motoren bevarer"-kontrakten (§4.4):
ældste pin øverst, så en etableret forside ikke hopper når nye pins tilføjes. Egen fil — pins
vedrører alle korttyper, ikke kun stories.

- [ ] **Step 1: Skriv de fejlende tests** — `packages/feed/src/__tests__/pins.test.ts`:

```ts
import { describe, expect, it } from 'vitest';
import { buildFeedPins } from '../pins';

describe('buildFeedPins', () => {
  it('sorterer oprettet_naar stigende med kort_noegle som tiebreak', () => {
    const out = buildFeedPins([
      { kort_noegle: 'portrait:9', handling: 'pin',   oprettet_naar: '2026-07-02T10:00:00Z' },
      { kort_noegle: 'story:2',    handling: 'skjul', oprettet_naar: '2026-07-01T10:00:00Z' },
      { kort_noegle: 'arkiv:5',    handling: 'pin',   oprettet_naar: '2026-07-02T10:00:00Z' },
    ]);
    expect(out).toEqual([
      { kortNoegle: 'story:2',    handling: 'skjul' },
      { kortNoegle: 'arkiv:5',    handling: 'pin' },
      { kortNoegle: 'portrait:9', handling: 'pin' },
    ]);
  });

  it('NULL-tidsstempel sorteres sidst', () => {
    const out = buildFeedPins([
      { kort_noegle: 'a', handling: 'pin', oprettet_naar: null },
      { kort_noegle: 'b', handling: 'pin', oprettet_naar: '2026-07-01T00:00:00Z' },
    ]);
    expect(out.map((p) => p.kortNoegle)).toEqual(['b', 'a']);
  });

  it('ukendt handling filtreres; tomme input giver []', () => {
    expect(buildFeedPins([{ kort_noegle: 'x', handling: 'fremhaev', oprettet_naar: null }])).toEqual([]);
    expect(buildFeedPins([])).toEqual([]);
  });
});
```

- [ ] **Step 2: Kør — verificér FAIL** (`Cannot find module '../pins'`).
- [ ] **Step 3: Implementér:**

```ts
// packages/feed/src/pins.ts
// Pin/skjul-normalisering (fase3-design.md §5.1): rå feed_pin-rækker → deterministisk
// sorteret FeedPinInput[]. "Klienten sorterer, motoren bevarer": blok-ordenen i
// buildFeedOrder er ren input-orden, og motoren holdes fri for tidsstempel-viden.
import type { FeedPinInput } from './types';

export interface FeedPinRow { kort_noegle: string; handling: string; oprettet_naar: string | null; }

export function buildFeedPins(rows: FeedPinRow[]): FeedPinInput[] {
  return rows
    .filter((r): r is FeedPinRow & { handling: 'pin' | 'skjul' } =>
      r.handling === 'pin' || r.handling === 'skjul')
    .sort((a, b) => {
      if (a.oprettet_naar == null && b.oprettet_naar != null) return 1;
      if (a.oprettet_naar != null && b.oprettet_naar == null) return -1;
      if (a.oprettet_naar != null && b.oprettet_naar != null && a.oprettet_naar !== b.oprettet_naar) {
        return a.oprettet_naar.localeCompare(b.oprettet_naar);
      }
      return a.kort_noegle.localeCompare(b.kort_noegle);
    })
    .map((r) => ({ kortNoegle: r.kort_noegle, handling: r.handling }));
}
```

- [ ] **Step 4: Kør — verificér PASS** + `tsc` grøn.
- [ ] **Step 5: Commit** — `feat(feed): buildFeedPins — deterministisk pin-normalisering (skive 3)`.

---

## Task 4: Motor — `historie`-kort: `buildStorieKort` + dedup + scoring (skive 2)

**Files:**
- Modify: `packages/feed/src/story.ts` (+ `__tests__/story.test.ts`),
  `packages/feed/src/score.ts` (+ `__tests__/score.test.ts` hvis den findes — ellers læg
  score-testene i `story.test.ts`), `packages/feed/src/pool.ts` (+ `__tests__/pool.test.ts`).

**Interfaces (spec §4.2–§4.3):**
- `buildStorieKort(model: Model, storieBy: StorieBy, haendelserBy: HaendelserBy, todayISO:
  string): { cards: FeedCard[]; usedHaendelseIds: Set<string> }` (i `story.ts`): ét kort pr.
  publiceret story hvis personen findes i `model.byId` (ukendt id ⇒ udelades tavst, som
  `buildArkivKort`); `id: 'story:' + item.id`; `kicker: 'Historie'`; `aarLabel` = `dateRaw`
  foretrukket, ellers årstal af `dato.min`, ellers `null` (ordret arkiv-reglen, `pool.ts:81-83`);
  `kategori` arves fra den forankrede hændelse via opslag i `haendelserBy[personId]` (intet
  anker/ikke i klient-settet ⇒ `null`); `nyPubliceret` sat når `publiceretDato` ligger 0–30
  dage før injiceret `todayISO` (streng-dato-aritmetik via `Date.parse` på ISO-strenge — aldrig
  `Date.now`); stabil `byIdStr`-sortering; hver genereret story med `haendelseId` lægger id'et
  i `usedHaendelseIds`.
- `score.ts`: `BASE.historie = 1.2` står allerede (task 2); nyt signal i `score()` (linje 33-42),
  dokumenteret ved siden af arkiv-boostet: `if (card.kind === 'historie' && card.nyPubliceret)
  s *= 2;` — hviler på ægte `publiceret_dato` (koncept §9.5, aldrig fabrikerede tidsstempler).
  Bogmærke (×1,5) og seen gælder automatisk (`personId`/`id` som alle andre kort).
- `pool.ts`: `buildPortraitAndCitat(model, excludeId = null, haendelserBy = {},
  usedStorieHaendelseIds: ReadonlySet<string> = new Set())` — citat-kandidatfiltret
  (`pool.ts:43-45`) udvides med `&& !usedStorieHaendelseIds.has(item.id)` (default tomt sæt =
  bagudkompatibel). `buildArkivKort` er UÆNDRET — `order.ts` (task 5) sender unionen
  `usedHaendelseIds ∪ usedCitatHaendelseIds` som dens eksisterende eksklusions-parameter.

- [ ] **Step 1: Skriv de fejlende tests.** Udvid `story.test.ts`:

```ts
import { buildModel } from '@daa/core';
import { buildStorieKort } from '../story';
import { score } from '../score';
import type { HaendelserBy, Model, StorieBy, StoryItem } from '../types';

function mkModel(ids: string[]): Model {
  return buildModel({
    persons: ids.map((id) => ({ id, name: 'Person ' + id, born: null, died: null,
      years: '', title: '', bio: '', privat: false })),
    unions: [], parentChild: [],
  }) as unknown as Model;
}
function storie(id: string, over: Partial<StoryItem> = {}): StoryItem {
  return { id, titel: null, tekst: 'En kort redaktionel minihistorie om personens liv og virke.',
    dato: { min: null, max: null, qualifier: null }, dateRaw: null,
    haendelseId: null, publiceretDato: null, kilde: null, ...over };
}

describe('buildStorieKort', () => {
  const m = mkModel(['p1', 'p2']);

  it('aarLabel: dateRaw foretrukket, ellers år af min, ellers null', () => {
    const by: StorieBy = { p1: [
      storie('1', { dateRaw: 'ca. 1580', dato: { min: '1580-01-01', max: null, qualifier: null } }),
      storie('2', { dato: { min: '1671-05-02', max: '1671-05-02', qualifier: 'exact' } }),
      storie('3'),
    ] };
    const { cards } = buildStorieKort(m, by, {}, '2026-07-19');
    expect(cards.map((c) => c.kind === 'historie' ? c.aarLabel : null)).toEqual(['ca. 1580', '1671', null]);
  });

  it('kategori arves fra forankret hændelse; null uden anker eller ukendt hændelse', () => {
    const hs: HaendelserBy = { p1: [{ id: 'h9', klausul: 'x', kategori: 'krig',
      dato: { min: null, max: null, qualifier: null }, dateRaw: null,
      interessant: false, rygrad: false, kilde: null }] };
    const by: StorieBy = { p1: [
      storie('1', { haendelseId: 'h9' }), storie('2', { haendelseId: 'h404' }), storie('3'),
    ] };
    const { cards, usedHaendelseIds } = buildStorieKort(m, by, hs, '2026-07-19');
    expect(cards.map((c) => c.kind === 'historie' ? c.kategori : null)).toEqual(['krig', null, null]);
    expect([...usedHaendelseIds].sort()).toEqual(['h404', 'h9']); // begge forankrede id'er tælles
  });

  it('nyPubliceret: dag 30 inde, dag 31 ude — mod injiceret todayISO', () => {
    const by: StorieBy = { p1: [
      storie('1', { publiceretDato: '2026-06-19' }), // 30 dage før 2026-07-19 → inde
      storie('2', { publiceretDato: '2026-06-18' }), // 31 dage → ude
      storie('3'),                                   // ingen dato → ude
    ] };
    const { cards } = buildStorieKort(m, by, {}, '2026-07-19');
    expect(cards.map((c) => c.kind === 'historie' ? Boolean(c.nyPubliceret) : null))
      .toEqual([true, false, false]);
  });

  it('ukendt person udelades tavst; stabil sortering; tomme input', () => {
    const by: StorieBy = { spoegelse: [storie('1')], p2: [storie('3'), storie('2')] };
    const { cards } = buildStorieKort(m, by, {}, '2026-07-19');
    expect(cards.map((c) => c.id)).toEqual(['story:2', 'story:3']);
    expect(buildStorieKort(m, {}, {}, '2026-07-19').cards).toEqual([]);
  });
});

describe('score — historie', () => {
  const kort = { kind: 'historie' as const, id: 'story:1', personId: 'p1', titel: null,
    tekst: 't', aarLabel: null, kategori: null, kilde: null, kicker: 'Historie' };
  const ctx = { bookmarkedIds: new Set<string>(), seenWeights: {} };
  it('BASE.historie ligger over alle auto-kort', () => {
    const portraet = { kind: 'portrait' as const, id: 'portrait:p1', personId: 'p1', name: 'N',
      years: '', initials: 'N', title: null, bio: 'b', kicker: 'Portræt' };
    expect(score(kort, ctx)).toBeGreaterThan(score(portraet, ctx));
  });
  it('nyPubliceret fordobler', () => {
    expect(score({ ...kort, nyPubliceret: true }, ctx)).toBeCloseTo(score(kort, ctx) * 2);
  });
});
```

  Udvid `pool.test.ts` (citat-dedup mod stories):

```ts
it('citat-kandidat med hændelses-id i usedStorieHaendelseIds filtreres (bio-fallback)', () => {
  // Find en citat-slot-person (stableHash % 4 === 0) med én brugbar klausul; når klausulens
  // hændelses-id står i story-sættet, falder citatet tilbage til firstQuotableSentence(bio).
  const persons = Array.from({ length: 8 }, (_, i) => person('p' + i, { bio: LONG_BIO }));
  const m = mkModel(persons);
  const citatPerson = persons.find((p) => stableHash(p.id) % 4 === 0)!;
  const hs: HaendelserBy = { [citatPerson.id]: [haendelse('h1')] };
  const uden = buildPortraitAndCitat(m, null, hs);
  const med = buildPortraitAndCitat(m, null, hs, new Set(['h1']));
  expect(uden.usedCitatHaendelseIds.has('h1')).toBe(true);
  expect(med.usedCitatHaendelseIds.has('h1')).toBe(false); // klausulen er ikke længere valgbar
  expect(med.citater.find((c) => c.id === 'citat:' + citatPerson.id)).toBeDefined(); // bio-fallback
});

it('regressionsværn: buildPortraitAndCitat uden 4. argument ≡ fase 2-output', () => {
  const persons = Array.from({ length: 12 }, (_, i) => person('p' + i, { bio: LONG_BIO }));
  const m = mkModel(persons);
  const hs: HaendelserBy = Object.fromEntries(persons.map((p, i) => [p.id, [haendelse('h' + i)]]));
  expect(buildPortraitAndCitat(m, null, hs)).toEqual(buildPortraitAndCitat(m, null, hs, new Set()));
});
```

  (Genbrug `person`/`mkModel`/`haendelse`/`LONG_BIO`-hjælperne fra `pool.test.ts`'s eksisterende
  fixtures — samme form som i `order.test.ts:8-35`.)
- [ ] **Step 2: Kør — verificér FAIL** (`buildStorieKort` eksporteres ikke; pool-testens
  4. argument er en tsc-/runtime-fejl).
- [ ] **Step 3: Implementér.** `story.ts`-tilføjelsen:

```ts
import { byIdStr } from './pool';
import type { FeedCard, HaendelserBy, Model } from './types';

// Flagskibs-kortet (fase3-design.md §4.3): ét 'historie'-kort pr. publiceret story.
// usedHaendelseIds tråder dedup'en: en hændelse med publiceret historie optræder aldrig
// samtidig som arkiv- eller citat-kort — historien er opgraderingen (koncept §5).
export function buildStorieKort(
  model: Model,
  storieBy: StorieBy,
  haendelserBy: HaendelserBy,
  todayISO: string,
): { cards: FeedCard[]; usedHaendelseIds: Set<string> } {
  const cards: FeedCard[] = [];
  const usedHaendelseIds = new Set<string>();
  const todayMs = Date.parse(todayISO); // injiceret dato — motoren rører aldrig klokken
  for (const [personId, items] of Object.entries(storieBy)) {
    const p = model.byId[personId];
    if (!p) continue; // ikke-kanoniseret/ukendt id ⇒ udelades tavst (som buildArkivKort)
    for (const item of items) {
      if (item.haendelseId != null) usedHaendelseIds.add(item.haendelseId);
      const aarLabel = item.dateRaw != null && item.dateRaw !== ''
        ? item.dateRaw
        : item.dato.min?.slice(0, 4) ?? null;
      const anker = item.haendelseId == null
        ? undefined
        : (haendelserBy[personId] ?? []).find((h) => h.id === item.haendelseId);
      const dage = item.publiceretDato == null
        ? null
        : (todayMs - Date.parse(item.publiceretDato)) / 86400000;
      const nyPubliceret = dage != null && dage >= 0 && dage <= 30;
      cards.push({
        kind: 'historie', id: 'story:' + item.id, personId,
        titel: item.titel, tekst: item.tekst, aarLabel,
        kategori: anker?.kategori ?? null, kilde: item.kilde,
        ...(nyPubliceret ? { nyPubliceret: true as const } : {}),
        kicker: 'Historie',
      });
    }
  }
  return { cards: cards.sort(byIdStr), usedHaendelseIds };
}
```

  `pool.ts`: udvid `buildPortraitAndCitat`-signaturen (linje 29-33) med
  `usedStorieHaendelseIds: ReadonlySet<string> = new Set()` og kandidatfiltret (linje 43-45) med
  `&& !usedStorieHaendelseIds.has(item.id)`. `score.ts`: boost-linjen efter arkiv-boostet
  (linje 36). Bemærk at `usedHaendelseIds` tilføjes for ALLE forankrede stories hos kendte
  personer — også når ankeret ikke længere findes i `haendelserBy` (dinglende anker skader ikke:
  der findes så heller intet arkiv-kort at ekskludere).
- [ ] **Step 4: Kør — verificér PASS** (hele pakke-suiten + `tsc`).
- [ ] **Step 5: Commit** — `feat(feed): buildStorieKort + historie-scoring + citat-dedup (skive 2)`.

---

## Task 5: Motor — pins/skjul i `buildFeedOrder` + regressions-invariant (skive 2)

**Files:**
- Modify: `packages/feed/src/order.ts`, `packages/feed/src/__tests__/order.test.ts`.

**Interfaces (spec §4.4–§4.5):** `buildFeedOrder` læser `inputs.storieBy`/`inputs.pins`;
skjul-filter FØR scoring; pin = top-låst blok allerøverst i input-orden (R1/R2 relakseret
indbyrdes — kortene pushes direkte); positionslåse forskydes med blokkens længde `P`; INGEN
ekstra `rng()`-kald; dinglende nøgler ignoreres tavst. Kommentaren i `order.ts` dokumenterer de
to ortogonale skjul-stier (indholds-dom pr. hændelse vs. kurering pr. kort-id).

- [ ] **Step 1: Skriv de fejlende tests.** Udvid `order.test.ts` (genbrug `person`/`mkModel`/
  `rigModel`/`rigAux`/`baseInputs`/`haendelse`-hjælperne; tilføj `storie`-hjælperen fra task 4's
  testfil eller duplikér den lokalt):

```ts
// --- fase 3: regressions-invariant + pins/skjul -------------------------------
describe('buildFeedOrder — fase 3', () => {
  it('REGRESSIONS-INVARIANT: uden stories og pins er ordningen dybt identisk med fase 2', () => {
    const model = rigModel(40);
    const aux = rigAux(12);
    for (let seed = 0; seed < 50; seed++) {
      const fase2 = buildFeedOrder(model, aux, baseInputs({ seed }));
      expect(buildFeedOrder(model, aux, baseInputs({ seed, storieBy: {}, pins: [] }))).toEqual(fase2);
    }
    // også med hændelses-input (fase 2's fulde flade):
    const hs: HaendelserBy = Object.fromEntries(
      Array.from({ length: 20 }, (_, i) => ['p' + i, [haendelse('h' + i)]]));
    const a = buildFeedOrder(model, aux, baseInputs({ seed: 7, haendelserBy: hs }));
    expect(buildFeedOrder(model, aux, baseInputs({ seed: 7, haendelserBy: hs, storieBy: {}, pins: [] }))).toEqual(a);
  });

  it('pin-blok står allerførst og i input-orden — også to ens kinds i træk (R1 relakseret)', () => {
    const m = rigModel(20);
    const pins = [
      { kortNoegle: 'portrait:p3', handling: 'pin' as const },
      { kortNoegle: 'portrait:p1', handling: 'pin' as const },
    ];
    for (const seed of [1, 2, 3]) {
      const cards = buildFeedOrder(m, EMPTY_AUX, baseInputs({ seed, pins }));
      expect(cards[0].id).toBe('portrait:p3');
      expect(cards[1].id).toBe('portrait:p1');
    }
  });

  it('positionslåse forskydes med P: dagensperson i [P..P+2], slægt i [P+3..P+9]', () => {
    const persons = Array.from({ length: 15 }, (_, i) => person('p' + i, { bio: LONG_BIO }));
    const m = mkModel(persons);
    const pins = [
      { kortNoegle: 'portrait:p1', handling: 'pin' as const },
      { kortNoegle: 'portrait:p2', handling: 'pin' as const },
    ];
    const cards = buildFeedOrder(m, EMPTY_AUX, baseInputs({ seed: 5, pins }));
    const P = 2;
    const idx = cards.findIndex((c) => c.kind === 'dagensperson');
    expect(idx).toBeGreaterThanOrEqual(P);
    expect(idx).toBeLessThanOrEqual(P + 2);
  });

  it('pin overlever seenWeights=0; skjult kort-id findes aldrig i output', () => {
    const m = mkModel([person('a', { bio: LONG_BIO }), person('b', { bio: LONG_BIO })]);
    const medPin = buildFeedOrder(m, EMPTY_AUX, baseInputs({
      seenWeights: { 'portrait:a': 0 },
      pins: [{ kortNoegle: 'portrait:a', handling: 'pin' }],
    }));
    expect(medPin[0]?.id).toBe('portrait:a');
    const medSkjul = buildFeedOrder(m, EMPTY_AUX, baseInputs({
      pins: [{ kortNoegle: 'portrait:a', handling: 'skjul' }],
    }));
    expect(medSkjul.some((c) => c.id === 'portrait:a')).toBe(false);
  });

  it('dinglende pin/skjul er ufarlig: output identisk med uden dem', () => {
    const m = rigModel(20);
    const uden = buildFeedOrder(m, EMPTY_AUX, baseInputs({ seed: 3 }));
    const med = buildFeedOrder(m, EMPTY_AUX, baseInputs({ seed: 3, pins: [
      { kortNoegle: 'story:404', handling: 'pin' },
      { kortNoegle: 'arkiv:404', handling: 'skjul' },
    ] }));
    expect(med).toEqual(uden);
  });

  it('defensivt: ugyldig pin+skjul på samme nøgle degraderer til skjul', () => {
    // Umulig pr. DB-kontrakt (UNIQUE kort_noegle) — testen dokumenterer at skjul filtreres
    // FØR pin-udtræk, så en korrupt dobbelt-input aldrig kan tvinge et skjult kort frem.
    const m = mkModel([person('a', { bio: LONG_BIO }), person('b', { bio: LONG_BIO })]);
    const cards = buildFeedOrder(m, EMPTY_AUX, baseInputs({ pins: [
      { kortNoegle: 'portrait:a', handling: 'skjul' },
      { kortNoegle: 'portrait:a', handling: 'pin' },
    ] }));
    expect(cards.some((c) => c.id === 'portrait:a')).toBe(false);
  });

  it('historie-kort dominerer statistisk (BASE 1.2) og dedup holder end-to-end', () => {
    const persons = Array.from({ length: 24 }, (_, i) => person('p' + i, { bio: LONG_BIO }));
    const m = mkModel(persons);
    const hs: HaendelserBy = Object.fromEntries(persons.map((p, i) => [p.id, [haendelse('h' + i)]]));
    const target = persons[5];
    const sb: StorieBy = { [target.id]: [storie('s1', { haendelseId: hs[target.id][0].id })] };
    const seeds = Array.from({ length: 30 }, (_, i) => i + 1);
    let historieSum = 0; let portraetSum = 0;
    for (const seed of seeds) {
      const cards = buildFeedOrder(m, EMPTY_AUX, baseInputs({ seed, haendelserBy: hs, storieBy: sb }));
      expect(cards.some((c) => c.id === 'story:s1')).toBe(true);
      expect(cards.some((c) => c.id === 'arkiv:' + hs[target.id][0].id)).toBe(false); // dedup
      expect(cards.some((c) => c.kind === 'citat' && c.personId === target.id
        && c.quote === hs[target.id][0].klausul)).toBe(false); // aldrig citat af samme klausul
      historieSum += cards.findIndex((c) => c.id === 'story:s1');
      portraetSum += cards.findIndex((c) => c.kind === 'portrait');
    }
    expect(historieSum / seeds.length).toBeLessThan(portraetSum / seeds.length + 6); // statistisk tidlig
  });

  it('determinisme med storieBy+pins; createFeedStream leverer pin-blokken i første side', () => {
    const m = rigModel(20);
    const inputs = baseInputs({ seed: 4,
      storieBy: { p1: [storie('s1')] },
      pins: [{ kortNoegle: 'story:s1', handling: 'pin' }] });
    expect(buildFeedOrder(m, EMPTY_AUX, inputs)).toEqual(buildFeedOrder(m, EMPTY_AUX, inputs));
    const stream = createFeedStream(m, EMPTY_AUX, inputs);
    expect(stream.next(12)[0].id).toBe('story:s1');
  });
});
```

  (Tilføj `createFeedStream`, `StorieBy`, `EMPTY_AUX` m.fl. til testfilens imports efter behov.)
- [ ] **Step 2: Kør — verificér FAIL** (pins/storieBy ignoreres endnu: pin-blok-, skjul- og
  dedup-tests fejler; regressions-invarianten er grøn fra start — det er meningen).
- [ ] **Step 3: Implementér** i `buildFeedOrder` (`order.ts:96-240`) — de fem hunks:

```ts
// (1) efter `const haendelserBy = inputs.haendelserBy ?? {};` (linje 99):
const storieBy = inputs.storieBy ?? {};
const pins = inputs.pins ?? [];
// To skjul-stier sameksisterer bevidst og ORTOGONALT (fase3-spec §4.4):
// haendelse.feed_status='skjult' er en indholds-dom pr. HÆNDELSE (håndhævet i RLS +
// klient-join — hændelsen når aldrig motoren i nogen kort-form), mens feed_pin 'skjul'
// er kurering pr. KORT-ID og kan ramme vilkårlige korttyper. Ingen erstatter den anden.
const hideSet = new Set(pins.filter((p) => p.handling === 'skjul').map((p) => p.kortNoegle));
const pinKeys = pins.filter((p) => p.handling === 'pin').map((p) => p.kortNoegle);

// (2) kandidat-opbygningen (linje 103-121): buildStorieKort kaldes FØRST, sættet trådes videre:
const { cards: storieKort, usedHaendelseIds } = buildStorieKort(model, storieBy, haendelserBy, inputs.todayISO);
const { portraits, citater, usedCitatHaendelseIds } = buildPortraitAndCitat(
  model, dagensPersonId, haendelserBy, usedHaendelseIds,
);
const arkivEksklusion = new Set([...usedHaendelseIds, ...usedCitatHaendelseIds]);
// …candidateCards-listen udvides med `...storieKort` efter `...citater`, og
// buildArkivKort(model, haendelserBy, arkivEksklusion) erstatter det gamle 3. argument.

// (3) skjul-filter FØR scoring + pin-udtræk FØR score>0-filteret (linje 123-127 erstattes):
const visibleCards = hideSet.size > 0
  ? candidateCards.filter((card) => !hideSet.has(card.id))
  : candidateCards;
// Pin = top-låst blok: udtræk før score>0-filteret (pin vinder over seenWeights=0), i
// pins-arrayets orden (klient-sorteret, §5.1). Dinglende nøgler ignoreres tavst.
// INGEN rng()-kald her — forudsætningen for regressions-invarianten.
const cardById = new Map(visibleCards.map((card) => [card.id, card]));
const pinnedBlock: FeedCard[] = [];
const pinnedIds = new Set<string>();
for (const key of pinKeys) {
  const card = cardById.get(key);
  if (card && !pinnedIds.has(card.id)) { pinnedBlock.push(card); pinnedIds.add(card.id); }
}
const ctx = toScoreContext(inputs);
const scoredPool: ScoredCard[] = visibleCards
  .filter((card) => !pinnedIds.has(card.id))
  .map((card) => ({ card, score: score(card, ctx) }))
  .filter((c) => c.score > 0);

// (4) positionslåse forskudt med P (linje 141-154 justeres — P=0 ⇒ identisk aritmetik):
const P = pinnedBlock.length;
const totalBeforeTerminal = P + scoredPool.length
  + (lockedDagensPerson ? 1 : 0) + (lockedSlaegt ? 1 : 0);
const dagensPosition = lockedDagensPerson
  ? Math.min(P + Math.floor(rng() * 3), Math.max(P, totalBeforeTerminal - 1))
  : -1;
let slaegtPosition = lockedSlaegt
  ? Math.min(P + 3 + Math.floor(rng() * 7), Math.max(P, totalBeforeTerminal - 1))
  : -1;
if (slaegtPosition === dagensPosition) {
  slaegtPosition = Math.max(P, totalBeforeTerminal - 1);
}

// (5) ordered forudfyldes med blokken (linje 163) — while-løkken er i øvrigt URØRT;
// rytmereglerne læser den faktiske ordered-liste, så blokken tæller med i R1/R2/R3 udadtil:
const ordered: FeedCard[] = [...pinnedBlock];
```

  Er et låst kort selv pinnet (eller skjult), finder `takeLocked` intet i `scoredPool`, og
  låsen udgår tavst — pin/skjul vinder (spec §4.4). Import `buildStorieKort` fra `./story`.
- [ ] **Step 4: Kør — verificér PASS** (hele pakke-suiten inkl. de EKSISTERENDE fase 1/2-tests
  og ydelses-loftet + `tsc`).
- [ ] **Step 5: Commit** — `feat(feed): pins/skjul i buildFeedOrder — top-låst blok + regressions-invariant (skive 2)`.

---

## Task 6: Mobil — story-/pin-load (skive 3)

**Files:**
- Create: `mobile/src/data/story.ts`, `mobile/src/data/feedPins.ts`,
  `mobile/src/data/__tests__/story.test.ts`, `mobile/src/data/__tests__/feedPins.test.ts`.
- Modify: `mobile/src/data/load.ts`, `mobile/src/store/useStore.ts`,
  `mobile/src/app/(tabs)/index.tsx`.

**Interfaces (spec §5.2 — hændelses-loaderen `mobile/src/data/haendelser.ts` er skabelonen 1:1):**
- `story.ts`: kopiér `IN_CHUNK = 200`/`chunkArray`/`fetchInChunks` fra `haendelser.ts:15-34`;
  `fetchStoryRows(sb): Promise<StoryRowsResult>` med tre queries og tolerant top-catch
  (`console.warn('[story] utilgængelig — historie-kort udelades:', e)` → tomt resultat):
  1) `sb.from('story').select('id,subjekt_id,haendelse_id,titel,tekst,date_min,date_max,date_qualifier,date_raw,status,publiceret_dato,privat').eq('subjekt_type','person').eq('status','publiceret').order('id')`
     via `getAll` fra `@daa/core` (status-filteret er payload-hygiejne + defense-in-depth — RLS
     håndhæver alligevel);
  2) `story_kilde` · `id,story_id,source_id,side` · chunked `.in('story_id', storyIds)`;
  3) `source` · `id,udgave` · chunked `.in('id', sourceIds)`.
  `loadStorieBy(sb, canonicalIdById): Promise<StorieBy>` = fetch + `buildStorieBy`.
- `feedPins.ts`: `fetchFeedPins(sb): Promise<FeedPinInput[]>` — én query
  `sb.from('feed_pin').select('kort_noegle,handling,oprettet_naar').order('oprettet_naar').order('kort_noegle')`
  via `getAll` → `buildFeedPins` (der uanset query-orden gen-sorterer deterministisk);
  catch → `[]` + `console.warn('[feedPins] utilgængelig — feed vises ukurateret:', e)`.
- `load.ts`: to nye parallelle promises ved siden af `haendelseRowsP` (linje 122-124):
  `const storyRowsP = fetchStoryRows(sb);` + `const feedPinsP = fetchFeedPins(sb);`; join efter
  collapse (ved linje 331-335): `const storyRows = await storyRowsP;` →
  `buildStorieBy(storyRows.rows, storyRows.kilder, storyRows.sources, collapsed.canonicalIdById)`
  + `const feedPins = await feedPinsP;`; nye `LoadResult`-felter (efter `haendelserBy`, linje
  65-67) `storieBy: StorieBy;` og `feedPins: FeedPinInput[];` med kommentarer i samme stil;
  returnér begge.
- `useStore.ts`: nye felter `storieBy: StorieBy` (init `{}`) og `feedPins: FeedPinInput[]`
  (init `[]`) ved siden af `haendelserBy` (linje 52-53 + 133); sat fra
  `res.storieBy ?? {}`/`res.feedPins ?? []` i `load()` (ved linje 187); SEED-fallback `{}`/`[]`
  med kommentarer "SEED bærer ingen stories — historie-kort udelades" / "SEED bærer ingen pins —
  feed'en vises ukurateret" (ved linje 220).
- `index.tsx`: læs `storieBy`/`feedPins` fra store (ved linje 44-45) og giv dem til
  `createFeedStream`-inputs som `storieBy` og `pins: feedPins` (linje 109-116, + begge i
  `useMemo`-dependency-listen).

- [ ] **Step 1: Skriv de fejlende tests** — `story.test.ts` (spejl af
  `mobile/src/data/__tests__/haendelser.test.ts` inkl. dens `fakeSupabase`-hjælper):

```ts
import { fetchStoryRows, loadStorieBy } from '../story';
// … kopiér fakeSupabase-hjælperen fra __tests__/haendelser.test.ts (linje 5-31) …

const row = (id: number, subjektId = 'p1') => ({
  id, subjekt_id: subjektId, haendelse_id: null, titel: null, tekst: 'Historie ' + id,
  date_min: null, date_max: null, date_qualifier: null, date_raw: null,
  status: 'publiceret', publiceret_dato: null, privat: false,
});

describe('fetchStoryRows', () => {
  it('henter story → story_kilde → source i tre led', async () => {
    const { sb, fromCalls } = fakeSupabase({
      story: [row(1), row(2)],
      story_kilde: [{ id: 10, story_id: 1, source_id: 20, side: '112' }],
      source: [{ id: 20, udgave: '1939' }],
    });
    const out = await fetchStoryRows(sb as never);
    expect(out.rows).toHaveLength(2);
    expect(out.kilder).toHaveLength(1);
    expect(out.sources).toHaveLength(1);
    expect(fromCalls).toEqual(['story', 'story_kilde', 'source']);
  });

  it('chunker mere end 200 story-id’er', async () => {
    const rows = Array.from({ length: 450 }, (_, i) => row(i, 'p' + i));
    const kilder = rows.map((r) => ({ id: 1000 + r.id, story_id: r.id, source_id: 20, side: null }));
    const { sb, inCalls } = fakeSupabase({ story: rows, story_kilde: kilder, source: [{ id: 20, udgave: '1939' }] });
    const out = await fetchStoryRows(sb as never);
    expect(out.kilder).toHaveLength(450);
    expect(inCalls.filter((call) => call.table === 'story_kilde')).toHaveLength(3);
  });

  it('fejl giver tomt resultat + warn; tom tabel stopper uden følgequeries', async () => {
    const warn = jest.spyOn(console, 'warn').mockImplementation(() => undefined);
    const broken = { from: () => { throw new Error('netværksfejl'); } };
    await expect(fetchStoryRows(broken as never)).resolves.toEqual({ rows: [], kilder: [], sources: [] });
    expect(warn).toHaveBeenCalled();
    warn.mockRestore();
    const { sb, fromCalls } = fakeSupabase({ story: [] });
    await expect(fetchStoryRows(sb as never)).resolves.toEqual({ rows: [], kilder: [], sources: [] });
    expect(fromCalls).toEqual(['story']);
  });
});

describe('loadStorieBy', () => {
  it('joiner og kanoniserer person-id', async () => {
    const { sb } = fakeSupabase({
      story: [row(1, 'alias')],
      story_kilde: [{ id: 10, story_id: 1, source_id: 20, side: '112' }],
      source: [{ id: 20, udgave: '1939' }],
    });
    const out = await loadStorieBy(sb as never, { alias: 'kanonisk' });
    expect(out.kanonisk).toEqual([expect.objectContaining({ id: '1', kilde: 'DAA 1939, s. 112' })]);
  });
});
```

  `feedPins.test.ts`: rows → sorteret `FeedPinInput[]` (mock `feed_pin`-tabellen); fejl → `[]`
  + warn — samme `fakeSupabase`-form.
- [ ] **Step 2: Kør — verificér FAIL** (`npx tsc --noEmit && npm test` fra `mobile/` —
  modulerne findes ikke).
- [ ] **Step 3: Implementér** (loaderne + integration i `load.ts`/`useStore.ts`/`index.tsx`
  jf. Interfaces).
- [ ] **Step 4: Kør — verificér PASS**; `npx tsc --noEmit && npm test` grøn fra `mobile/`.
  Felterne er no-op'er i UI indtil task 8 (motoren bruger dem allerede fra task 5).
- [ ] **Step 5: Commit** — `feat(feed): story/pin-load mobil — tolerant fetch + store-felter (skive 3)`.

---

## Task 7: Web — story-/pin-load + resume (skive 3)

**Files:**
- Create: `web/src/data/story.ts`, `web/src/data/feedPins.ts`,
  `web/src/data/__tests__/story.test.ts`, `web/src/data/__tests__/feedPins.test.ts`.
- Modify: `web/src/components/feed/FeedStreamView.tsx`, `web/src/components/HomeView.tsx`.

**Interfaces:**
- `web/src/data/story.ts` = web-spejl af task 6 (modul-`supabase` fra `../supabase` i stedet for
  parameter — præcis som `web/src/data/haendelser.ts` afviger fra mobilens): `fetchStoryRows()`
  + `loadStorieBy(canonicalIdById)`. `web/src/data/feedPins.ts`: `fetchFeedPins():
  Promise<FeedPinInput[]>` — samme query/catch som mobilens.
- **Bevidst afvigelse fra rent spejl (spec §7.4 begrunder):** `feedPins` hentes i **HomeView**
  (ikke i FeedStreamView) — forsidens startpersoner (task 12) og feed-strømmen skal dele ÉT
  load. I `HomeView.tsx`: ny state `const [feedPins, setFeedPins] = useState<FeedPinInput[]>([]);`
  + mount-effekt med `alive`-guard (mønstret fra `FeedStreamView.tsx:82-89`), og `feedPins`
  gives som NY prop til `<FeedStreamView … feedPins={feedPins} />`.
- `FeedStreamView.tsx`: `storieBy` hentes ved mount efter `haendelserBy`-mønstret (ny state ved
  linje 81, hent i samme `useEffect` linje 82-89: `void loadStorieBy(canon).then((sb) => { if
  (alive) setStorieBy(sb); });`); prop `feedPins: FeedPinInput[]` tilføjes; begge føjes til
  `createFeedStream`-inputs (linje 118-122: `storieBy, pins: feedPins`) og til
  rebuild-effektens dependency-liste (linje 143) — strømmen genopbygges med samme seed og
  genoptages via `resumeStream` (append-kontrakten er fase 1-testet og gratis).

- [ ] **Step 1: Skriv de fejlende tests** (vitest; kopiér mock-opsætningen af `../supabase` fra
  `web/src/data/__tests__/haendelser.test.ts`): story-kæden (tre led), chunking, status-filter i
  query-kæden (assert at `.eq('status','publiceret')` kaldes), fejl → tomt + warn; feedPins:
  sortering via `buildFeedPins`, fejl → `[]`.
- [ ] **Step 2: Kør — verificér FAIL** (`npm run test` fra `web/`).
- [ ] **Step 3: Implementér** (loadere + HomeView-state + FeedStreamView-wiring).
- [ ] **Step 4: Kør — verificér PASS** + `npm run build` grøn.
- [ ] **Step 5: Commit** — `feat(feed): story/pin-load web + resume ved ankomst (skive 3)`.

---

## Task 8: Kort-views i begge apps (skive 4)

**Files:**
- Modify: `web/src/components/feed/FeedCardView.tsx` (switch, ny case efter `case 'arkiv'`
  linje 55-73), `mobile/src/components/feed/FeedCardView.tsx` (ditto, linje 82-101),
  `web/src/components/feed/FeedStreamView.tsx` (`openCard`-switch, linje 204-213),
  `mobile/src/app/(tabs)/index.tsx` (forsidens tilsvarende åbn-handler — find switchen over
  `card.kind` og tilføj `'historie'` til person-navigations-casen).

**Regler (spec §6):** flagskib i redaktionel ro — kicker `'Historie'`, titel kun når sat,
brødteksten som krop, `aarLabel` + kategori diskret (arkiv-idiomet), kildefod `efter {kilde}`
("efter"-præfikset lever i view-laget, §5.1), diskret "Nyt i arkivet"-markør ved
`nyPubliceret` (ærligt — ægte publiceringsdato). KUN tokens fra `theme.ts`/`tokens.ts`.
Navigation: hele kortet åbner personen (som portræt). Ingen AI-oprindelses-visning (moot, §12).

- [ ] **Step 1: Implementér web-casen** (ingen unit-test af ren JSX — fase 1/2-præcedens):

```tsx
case 'historie':
  return (
    <div style={{ ...cardBase, cursor: 'pointer' }} onClick={() => onOpen(card)}>
      <div style={headerRow}>
        <span style={kicker}>{card.kicker}</span>
        {save}
      </div>
      {(card.aarLabel || card.kategori || card.nyPubliceret) ? (
        <div style={{ display: 'flex', gap: 9, alignItems: 'center', flexWrap: 'wrap', marginTop: 9 }}>
          {card.aarLabel ? <span style={{ fontFamily: T.mono, fontSize: 9.5, color: T.bordeaux }}>{card.aarLabel}</span> : null}
          {card.kategori ? <span style={{ fontFamily: T.mono, fontSize: 8.5, color: T.muted2 }}>{card.kategori}</span> : null}
          {card.nyPubliceret ? <span style={{ fontFamily: T.mono, fontSize: 8.5, color: T.gold }}>Nyt i arkivet</span> : null}
        </div>
      ) : null}
      {card.titel ? <div style={{ fontFamily: T.serif, fontSize: 22, fontWeight: 600, color: T.ink, marginTop: 8 }}>{card.titel}</div> : null}
      <div style={{ fontFamily: T.sans, fontSize: 13.5, lineHeight: 1.55, color: T.ink, marginTop: 8 }}>{card.tekst}</div>
      {card.kilde ? <div style={{ fontFamily: T.sans, fontSize: 10.5, color: T.muted2, marginTop: 12 }}>efter {card.kilde}</div> : null}
    </div>
  );
```

  I `FeedStreamView.tsx`'s `openCard`: tilføj `case 'historie':` til person-gruppen
  (`case 'portrait': case 'citat': case 'arkiv': …`).
- [ ] **Step 2: Implementér mobil-casen** (samme struktur i tokens-idiomet — `CardHeaderRow` +
  `Serif`-titel + `Body`-tekst + `Mono`-metarække + kildefod som arkiv-kortets, linje 82-101;
  `Pressable` med `onOpen(card)`), og person-navigations-casen i `(tabs)/index.tsx`.
- [ ] **Step 3: Verificér manuelt** mod kopi-basen med seedede stories (genbrug task 1's
  verify-seed-form: en publiceret story m. kilde på en afdød person): historie-kortet renderes i
  browser + simulator med titel/tekst/kildefod; "Nyt i arkivet" vises ved frisk
  `publiceret_dato`; bogmærke-toggle virker; navigation åbner personen; mod TOM `story`-tabel:
  intet historie-kort, ingen konsol-fejl. `npx tsc --noEmit && npm test` (mobil) +
  `npm run test && npm run build` (web) grønne. Dokumentér hvad der er testet vs. manuelt
  verificeret.
- [ ] **Step 4: Commit** — `feat(feed): historie-kort-views mobil+web (skive 4)`.

---

## Task 9: Redaktion — write-lag i begge apps (skive 5)

**Files:**
- Modify: `mobile/src/data/redaktionWrite.ts` + `mobile/src/data/__tests__/redaktionWrite.test.ts`,
  `web/src/data/redaktionWrite.ts` + `web/src/data/__tests__/redaktionWrite.test.ts`
  (fortsat spejlpar — filernes egne "hold i sync"-kommentarer; delt-pakke-ekstraktion er kendt
  follow-up).

**Interfaces (spec §7.1 — `haendelseStatus`-caset, mobil `redaktionWrite.ts:59-62` / web `:60-63`,
er den direkte præcedens: validér felterne, returnér `{ fn, args }`, ellers `null`):**
- `Change.art`-unionen udvides i BEGGE apps med:
  `| 'opretStory' | 'redigerStory' | 'setStoryStatus' | 'sletStory' | 'setStoryKilder'
   | 'setFeedPin' | 'fjernFeedPin'`.
- Nye valgfrie felter på `Change` (flad felt-stil som `haendelseId`/`status`):
  `storyId?: number;` · `storyStatus?: 'kladde' | 'klar' | 'publiceret' | 'arkiveret';` ·
  `kortNoegle?: string;` · `handling?: 'pin' | 'skjul';` ·
  `kilder?: { sourceId: number; side?: string }[];` — story-feltværdier
  (titel/tekst/ankre/dato/privat) via det eksisterende `payload`-felt.
- Dry-run/LIVE er dermed gratis (`submitChange(change, { dryRun })`), og webs
  `planCall`-rolle-routing degraderer ikke-redaktører til `red_suggest`-staging uændret.

- [ ] **Step 1: Skriv de fejlende tests** (identiske cases i begge apps' suiter — jest hhv.
  vitest; web-varianten asserter desuden `planCall(…, 'medlem')` → `red_suggest`):

```ts
describe('buildRpcCall — story/feed_pin (fase 3)', () => {
  it('opretStory → red_opret_story med payload-felter', () => {
    expect(buildRpcCall({ art: 'opretStory', subjektType: 'person', subjektId: '7',
      payload: { tekst: 'En minihistorie.', titel: 'Slaget', haendelseId: 91, dateRaw: '1671' } }))
      .toEqual({ fn: 'red_opret_story', args: {
        p_subjekt_type: 'person', p_subjekt_id: 7, p_tekst: 'En minihistorie.',
        p_titel: 'Slaget', p_haendelse_id: 91, p_fact_id: null, p_relation_id: null,
        p_historical_event_id: null, p_date_min: null, p_date_max: null,
        p_date_qualifier: null, p_date_raw: '1671', p_privat: false } });
    expect(buildRpcCall({ art: 'opretStory', subjektType: 'person', subjektId: '7',
      payload: { tekst: '   ' } })).toBeNull(); // fail-closed: tom tekst
  });
  it('redigerStory → red_rediger_story; kræver storyId + tekst', () => {
    expect(buildRpcCall({ art: 'redigerStory', subjektType: 'person', subjektId: '7',
      storyId: 3, payload: { tekst: 'Omskrevet.', privat: true } }))
      .toMatchObject({ fn: 'red_rediger_story',
        args: { p_story_id: 3, p_tekst: 'Omskrevet.', p_privat: true } });
    expect(buildRpcCall({ art: 'redigerStory', subjektType: 'person', subjektId: '7',
      payload: { tekst: 'x' } })).toBeNull();
  });
  it('setStoryStatus validerer mod de fire koder', () => {
    expect(buildRpcCall({ art: 'setStoryStatus', subjektType: 'person', subjektId: '7',
      storyId: 3, storyStatus: 'publiceret' }))
      .toEqual({ fn: 'red_set_story_status', args: { p_story_id: 3, p_status: 'publiceret' } });
    expect(buildRpcCall({ art: 'setStoryStatus', subjektType: 'person', subjektId: '7',
      storyId: 3, storyStatus: 'udgivet' as never })).toBeNull();
  });
  it('sletStory / setStoryKilder / setFeedPin / fjernFeedPin', () => {
    expect(buildRpcCall({ art: 'sletStory', subjektType: 'person', subjektId: '7', storyId: 3 }))
      .toEqual({ fn: 'red_slet_story', args: { p_story_id: 3 } });
    expect(buildRpcCall({ art: 'setStoryKilder', subjektType: 'person', subjektId: '7',
      storyId: 3, kilder: [{ sourceId: 2, side: '112' }, { sourceId: 5 }] }))
      .toEqual({ fn: 'red_set_story_kilder', args: { p_story_id: 3,
        p_kilder: [{ source_id: 2, side: '112' }, { source_id: 5, side: null }] } });
    expect(buildRpcCall({ art: 'setStoryKilder', subjektType: 'person', subjektId: '7',
      storyId: 3 })).toBeNull();
    expect(buildRpcCall({ art: 'setFeedPin', subjektType: 'person', subjektId: '7',
      kortNoegle: 'portrait:12', handling: 'pin' }))
      .toEqual({ fn: 'red_set_feed_pin', args: { p_kort_noegle: 'portrait:12', p_handling: 'pin' } });
    expect(buildRpcCall({ art: 'setFeedPin', subjektType: 'person', subjektId: '7',
      kortNoegle: '  ', handling: 'pin' })).toBeNull();
    expect(buildRpcCall({ art: 'fjernFeedPin', subjektType: 'person', subjektId: '7',
      kortNoegle: 'portrait:12' }))
      .toEqual({ fn: 'red_fjern_feed_pin', args: { p_kort_noegle: 'portrait:12' } });
  });
});
```

- [ ] **Step 2: Kør — verificér FAIL** i begge apps (arterne findes ikke i unionen → tsc-fejl).
- [ ] **Step 3: Implementér** — nye cases i `buildRpcCall` (samme kode i begge apps, indsat
  efter `haendelseStatus`-caset):

```ts
const storyPayloadArgs = (p: Record<string, unknown>) => ({
  p_titel: (p.titel as string | null | undefined) ?? null,
  p_haendelse_id: p.haendelseId != null ? Number(p.haendelseId) : null,
  p_fact_id: p.factId != null ? Number(p.factId) : null,
  p_relation_id: p.relationId != null ? Number(p.relationId) : null,
  p_historical_event_id: p.historicalEventId != null ? Number(p.historicalEventId) : null,
  p_date_min: (p.dateMin as string | null | undefined) ?? null,
  p_date_max: (p.dateMax as string | null | undefined) ?? null,
  p_date_qualifier: (p.dateQualifier as string | null | undefined) ?? null,
  p_date_raw: (p.dateRaw as string | null | undefined) ?? null,
  p_privat: Boolean(p.privat),
});
if (c.art === 'opretStory') {
  const p = c.payload || {};
  const tekst = typeof p.tekst === 'string' ? p.tekst.trim() : '';
  if (!tekst) return null;
  return { fn: 'red_opret_story', args: {
    p_subjekt_type: c.subjektType, p_subjekt_id: sid, p_tekst: tekst, ...storyPayloadArgs(p) } };
}
if (c.art === 'redigerStory') {
  const p = c.payload || {};
  const tekst = typeof p.tekst === 'string' ? p.tekst.trim() : '';
  if (c.storyId == null || !Number.isFinite(c.storyId) || !tekst) return null;
  return { fn: 'red_rediger_story', args: {
    p_story_id: c.storyId, p_tekst: tekst, ...storyPayloadArgs(p) } };
}
if (c.art === 'setStoryStatus') {
  if (c.storyId == null || !Number.isFinite(c.storyId) || !c.storyStatus
      || !['kladde','klar','publiceret','arkiveret'].includes(c.storyStatus)) return null;
  return { fn: 'red_set_story_status', args: { p_story_id: c.storyId, p_status: c.storyStatus } };
}
if (c.art === 'sletStory') {
  if (c.storyId == null || !Number.isFinite(c.storyId)) return null;
  return { fn: 'red_slet_story', args: { p_story_id: c.storyId } };
}
if (c.art === 'setStoryKilder') {
  if (c.storyId == null || !Number.isFinite(c.storyId) || !Array.isArray(c.kilder)) return null;
  if (c.kilder.some((k) => k.sourceId == null || !Number.isFinite(Number(k.sourceId)))) return null;
  return { fn: 'red_set_story_kilder', args: { p_story_id: c.storyId,
    p_kilder: c.kilder.map((k) => ({ source_id: Number(k.sourceId), side: k.side ?? null })) } };
}
if (c.art === 'setFeedPin') {
  if (!c.kortNoegle || c.kortNoegle.trim() === '' || !c.handling
      || !['pin','skjul'].includes(c.handling)) return null;
  return { fn: 'red_set_feed_pin', args: { p_kort_noegle: c.kortNoegle, p_handling: c.handling } };
}
if (c.art === 'fjernFeedPin') {
  if (!c.kortNoegle || c.kortNoegle.trim() === '') return null;
  return { fn: 'red_fjern_feed_pin', args: { p_kort_noegle: c.kortNoegle } };
}
```

- [ ] **Step 4: Kør — verificér PASS** i begge apps; mobil `tsc` + web `build` grønne.
- [ ] **Step 5: Commit** — `feat(feed): redaktions-write for story/feed_pin — 7 nye Change-arter (skive 5)`.

---

## Task 10: Redaktion — read-lag + story-editor inline (skive 5, begge apps)

**Files:**
- Modify: `mobile/src/data/redaktionRead.ts` + `__tests__/redaktionRead.test.ts`,
  `web/src/data/redaktionRead.ts` + `__tests__/redaktionRead.test.ts`,
  `web/src/Redaktion.tsx` (person-editorens tidslinje-sektion, linje 695-720),
  `mobile/src/components/redaktion/HaendelseTidslinje.tsx`,
  `mobile/src/app/redaktion/person/[id].tsx`.

**Interfaces (spec §7.2 — `mapHaendelser`-mønstret, web `redaktionRead.ts:337-357` / mobil
`:350-369`, er skabelonen; fejl KASTER — aldrig tavs catch i redaktionen):**
- **`sourceId` på tidslinjen (additiv fase 2-udvidelse, nødvendig for kilde-prefill):** i
  `fetchHaendelserForPerson`s nested select ændres `source:source_id(titel,udgave)` →
  `source:source_id(id,titel,udgave)`; `RawHaendelseRow.narrative.source` får `id`;
  `HaendelsePost` + `TidslinjePost` får `sourceId?: number`; `mapHaendelser` sætter
  `sourceId: r.narrative?.source?.id != null ? Number(r.narrative.source.id) : undefined` og
  `buildTidslinje` fører den med på hændelses-poster (`sourceTitel`-linjerne er mønstret).
  Samme ændring i BEGGE apps.
- Ny mapper + fetch (begge apps):

```ts
export type StoryPost = {
  id: number; titel: string | null; tekst: string;
  dato: { min: string | null; max: string | null; qualifier: string | null; raw: string | null };
  status: 'kladde' | 'klar' | 'publiceret' | 'arkiveret';
  publiceretDato: string | null; privat: boolean;
  haendelseId: number | null; factId: number | null; relationId: number | null;
  historicalEventId: number | null;
  kilder: { sourceId: number; side: string | null; sourceTitel?: string }[];
};
export function mapStories(rows: RawStoryRow[]): StoryPost[];      // ren, testbar
export async function fetchStoriesForPerson(personId: string): Promise<StoryPost[]>;
```

  `fetchStoriesForPerson`-query (redaktion ser ALLE statusser via redaktion_read):
  `.from('story').select('id,titel,tekst,date_min,date_max,date_qualifier,date_raw,status,publiceret_dato,privat,haendelse_id,fact_id,relation_id,historical_event_id,story_kilde(id,source_id,side,source:source_id(titel,udgave))').eq('subjekt_type','person').eq('subjekt_id', Number(personId)).order('id')`
  — omvendt nesting (én-til-mange `story_kilde(…)`) er standard PostgREST; verificér mod
  kopi-basen, og fald ellers tilbage til to flade queries (samme forbehold som fase 2-planens
  task 11). `mapStories` sorterer kilderne på `id` og mapper snake→camel som `mapHaendelser`;
  fejl kaster (`throw new Error(error.message)`).
- Prefill-helper (ren, testbar — begge apps, i `redaktionRead.ts` ved tidslinje-typerne):

```ts
// Forudfyldning af story-editoren fra en hændelses-post (fase3-spec §7.2): klausulen er
// STARTPUNKT (redaktøren omskriver til ~40-90 ord — redaktionel norm, ikke validering),
// dato kopieres fra ankeret, kilden fra narrativ-source (+side).
export function storyPrefillFraPost(post: TidslinjePost): {
  tekst: string; haendelseId: number | null;
  dateMin: string | null; dateMax: string | null;
  dateQualifier: string | null; dateRaw: string | null;
  kilder: { sourceId: number; side?: string }[];
} {
  return {
    tekst: post.klausul,
    haendelseId: post.haendelseId ?? null,
    dateMin: post.dato.min, dateMax: post.dato.max,
    dateQualifier: post.dato.qualifier, dateRaw: post.dato.raw,
    kilder: post.sourceId != null
      ? [{ sourceId: post.sourceId, ...(post.side != null ? { side: post.side } : {}) }]
      : [],
  };
}
```

**Editor-UI (manuelt verificeret — ren JSX unit-testes ikke, fase 1/2-præcedens):**
- **Web** (`Redaktion.tsx`): i tidslinje-sektionen (linje 698-718) får hver hændelses-post en
  lille "+ Historie"-knap ved siden af status-pillerne; klik åbner en ny story-editor-boks
  (samme `T.panel`-boks-idiom som narrativ-editoren, linje 741) under tidslinjen, forudfyldt
  via `storyPrefillFraPost(post)`. Editoren viser: titel-felt, tekst-felt (med ordtæller mod
  40–90-normen — vejledning, ikke blokering), dato-felterne, kilde-listen (tilføj/fjern
  source + side; sendes samlet som `setStoryKilder` — erstat-semantik) og status-piller
  (kladde/klar/publiceret/arkiveret) i KONF-pille-mønstret (linje 701-713) — klik sender
  `run({ art: 'setStoryStatus', subjektType: 'person', subjektId: p.id, storyId, storyStatus },
  'Story-status')` gennem det normale dry-run/LIVE-flow (`run`-wrapperen, linje 422-441).
  Gem = `opretStory` (ny) eller `redigerStory` (eksisterende). Under sektionen listes
  subjektets stories i ALLE statusser (hent `fetchStoriesForPerson` sammen med
  `fetchHaendelserForPerson` i `loadPerson`-kæden; ny state `stories`). Arkivér-pillen ER den
  normale sletning; hård slet (`sletStory`) eksponeres IKKE i UI'et (§3.6 — psql/RPC direkte).
- **Mobil** (`HaendelseTidslinje.tsx`): ny valgfri prop
  `onNyHistorie?: (post: TidslinjePost) => void` — knap "Ny historie" pr. hændelses-post ved
  statusrækken (komponenten kalder ALDRIG selv write-laget — `FaktaKort`-arkitekturen).
  `person/[id].tsx` monterer den (linje 350-352), åbner et simpelt editor-sheet forudfyldt via
  `storyPrefillFraPost`, og sender `Change` gennem det eksisterende
  `SkrivePreviewSheet`-flow (linje 585-ff) med story-refetch på `onApplied` (som
  `refreshHaendelser`, linje 65).

- [ ] **Step 1: Skriv de fejlende tests** (begge apps): `mapStories` (rå rækker inkl. nested
  `story_kilde` → poster; alle statusser medtages; kilder sorteret på id; NULL-felter);
  `storyPrefillFraPost` (klausul/dato/anker kopieres; `sourceId` → én kilde m. side;
  post uden `sourceId` → tom kildeliste); `mapHaendelser` med `source.id` → `sourceId` sat.
- [ ] **Step 2: Kør — verificér FAIL** (begge apps).
- [ ] **Step 3: Implementér** read-laget (begge apps) + web-editoren + mobil-editoren.
- [ ] **Step 4: Kør — verificér PASS**; manuel verifikation mod kopi-basen (dry-run FØRST):
  "+ Historie" forudfylder klausul/dato/kilde; gem viser `red_opret_story`-kaldet i preview;
  LIVE-skriv → storyen står som kladde i listen; publicér-pillen sætter status + at historien
  dukker op som `historie`-kort i feed'en efter reload; arkivér fjerner den fra feed'et;
  fortryd i historikken virker. Ikke-redaktør-login på web → degraderer til `red_suggest`.
- [ ] **Step 5: Commit** — `feat(feed): story-editor inline på hændelses-tidslinjen mobil+web (skive 5)`.

---

## Task 11: Feed-styringsside (skive 5, KUN web)

**Files:**
- Create: `web/src/components/FeedStyring.tsx` (placeres ved siden af `SammenlignUdgaver` —
  importeret i `Redaktion.tsx:8` fra `./components/SammenlignUdgaver`),
  `web/src/components/__tests__/feedStyring.test.ts` (kun de rene helpers).
- Modify: `web/src/Redaktion.tsx` (`ENTITIES`-listen linje 43-57 + special-view-grenen linje
  468-473), `web/src/data/feedPins.ts` (rå-række-fetch), `web/src/data/redaktionRead.ts`
  (`fetchPubliceredeStories`).

**Interfaces (spec §7.3 — "kurerende, ikke CMS": tre handlinger plus oversigt, ingen
fakta-redigering herfra; mobil får IKKE denne side — kun task 10's inline-handlinger):**
- `ENTITIES` får `{ key: 'feed', label: 'Feed-styring', icon: '⚑' }` (før `sammenlign`), og
  render-grenen udvides: `entity === 'feed'` → fuldbredde-visning som `sammenlign`
  (`<FeedStyring role={role} model={model} run={run} />` — `run`-callbacken linje 422-441
  genbruges så dry-run/LIVE/`red_suggest`-routing er identisk med resten af redaktionen).
  `parseRedaktionPath`-grammatikken (linje 79-ff) håndterer allerede `/redaktion/feed`.
- `web/src/data/feedPins.ts` får (ud over task 7's `fetchFeedPins`) en rå variant til
  styringssiden: `fetchFeedPinRows(): Promise<FeedPinRow[]>` — samme query, men returnerer
  rækkerne med `oprettet_naar` (oversigten viser tidspunktet); fejl KASTER her (redaktions-
  reglen — siden skal vise fejlen, ikke et tomt "alt er vel").
- `web/src/data/redaktionRead.ts`: `fetchPubliceredeStories(): Promise<(StoryPost &
  { subjektId: number })[]>` — som `fetchStoriesForPerson` men `.eq('status','publiceret')`
  uden person-filter og med `subjekt_id` i select/mapping; fejl kaster.
- Rene, testbare helpers i `FeedStyring.tsx`:

```ts
// Kort-nøgler bygges af de kendte formater (koncept §3.4 / pool.ts-id'erne).
export function bygKortNoegle(slags: 'portrait' | 'story' | 'arkiv', id: string | number): string {
  return `${slags}:${id}`;
}
// Dinglende-markering (fase3-spec §7.3): efterprøves for de former vi KAN slå op lokalt;
// andre former er 'ukendt' — motoren ignorerer dem alligevel tavst (§4.4), oversigten
// skal blot være ærlig.
export function pinStatus(
  noegle: string,
  personIds: ReadonlySet<string>,
  storyIds: ReadonlySet<string>,
): 'ok' | 'dinglende' | 'ukendt' {
  if (noegle.startsWith('portrait:')) return personIds.has(noegle.slice(9)) ? 'ok' : 'dinglende';
  if (noegle.startsWith('story:'))    return storyIds.has(noegle.slice(6)) ? 'ok' : 'dinglende';
  return 'ukendt';
}
```

**Sidens tre sektioner (samme liste-/pille-idiom som resten af `Redaktion.tsx` — kun `T`-tokens):**
1. **Pins/skjul-oversigt:** alle `feed_pin`-rækker (nøgle · handling · `oprettet_naar`) med
   fjern-knap → `run({ art: 'fjernFeedPin', subjektType: 'feed_pin', subjektId: '', kortNoegle },
   'Fjern kurering')`. Dinglende nøgler (via `pinStatus` mod `model.byId`-id'erne og de
   publicerede storyers id'er) markeres visuelt.
2. **Publicerede stories:** liste (subjekt-navn via `model.byId`, titel/tekst-uddrag,
   `publiceret_dato`) med afpublicér-knap → `setStoryStatus(…, 'klar')` (tilbage til "færdig
   men ikke i feed" — arkivering er den stærkere handling og bor i editoren, task 10).
3. **Pin/skjul et kort:** person-søgefelt (genbrug `buildBrowse`-mønstret fra person-listen,
   linje 383-387) + story-liste; valgt emne + handling bygger nøglen med `bygKortNoegle`
   ('portrait:'+personId / 'story:'+storyId) og sender
   `run({ art: 'setFeedPin', …, kortNoegle, handling }, 'Kurér feed')`.

- [ ] **Step 1: Skriv de fejlende tests** (vitest): `bygKortNoegle` (tre former);
  `pinStatus` (portrait kendt/ukendt, story kendt/ukendt, `arkiv:`-nøgle → `'ukendt'`).
- [ ] **Step 2: Kør — verificér FAIL** (`npm run test` fra `web/` — modulet findes ikke).
- [ ] **Step 3: Implementér** helpers + side + data-fetches + Redaktion-wiring.
- [ ] **Step 4: Kør — verificér PASS** + `npm run build`; manuel verifikation mod kopi-basen:
  pin et portræt (dry-run-preview viser `red_set_feed_pin`) → LIVE → kortet står øverst i
  feed'en efter reload; skjul et kort → det forsvinder; fjern-knappen rydder; en bevidst
  dinglende nøgle markeres; afpublicér flytter storyen ud af feed'et. Ikke-redaktør →
  `red_suggest`-staging.
- [ ] **Step 5: Commit** — `feat(feed): feed-styringsside i web-redaktionen (skive 5)`.

---

## Task 12: Web-startpersoner fra pins (skive 5)

**Files:**
- Modify: `web/src/data/home.ts`, `web/src/components/HomeView.tsx`.
- Create/udvid: `web/src/data/__tests__/home.test.ts` (opret hvis den ikke findes).

**Interfaces (spec §7.4):**

```ts
export function forsideStartpersoner(
  model: Model,
  pins: FeedPinInput[],
  n: number,
): ModelPerson[];
```

Reglen: pins med `handling === 'pin'` og `kortNoegle` på formen `'portrait:<id>'`
(præfiks-parse — andre nøgleformer ignoreres her) slås op i `model.byId` (ukendt/
privat-bortfiltreret id springes over), pin-ordenen bevares; færre end `n` ⇒ fyld op med
`curatedFounders(model, …)` minus allerede valgte. **`curatedFounders` beholdes uændret som
fallback** — med nul pins er forsiden identisk med i dag. Opdatér home.ts-kommentaren
("Der findes endnu ingen redaktionel highlights-tabel" — nu findes den: `feed_pin`).

- [ ] **Step 1: Skriv de fejlende tests** (vitest — byg en lille model med `buildModel` som i
  `order.test.ts:18-20`): pins først og i pin-orden; dinglende portrait-pin ignoreres;
  `'story:'`/`'arkiv:'`-nøgler og `handling:'skjul'` ignoreres; fallback-udfyldning uden
  dubletter (en pinnet person optræder ikke dobbelt); tom pin-liste ⇒ resultatet er dybt
  identisk med `curatedFounders(model, n)`.
- [ ] **Step 2: Kør — verificér FAIL** (`forsideStartpersoner` eksporteres ikke).
- [ ] **Step 3: Implementér** i `home.ts`:

```ts
import type { FeedPinInput } from '@daa/feed';

// Startpersoner fra redaktionens portræt-pins (fase3-spec §7.4); curatedFounders er
// verificeret fallback — med nul pins er forsiden identisk med i dag.
export function forsideStartpersoner(
  model: Model,
  pins: FeedPinInput[],
  n: number,
): ModelPerson[] {
  const out: ModelPerson[] = [];
  const seen = new Set<string>();
  for (const pin of pins) {
    if (out.length >= n) break;
    if (pin.handling !== 'pin' || !pin.kortNoegle.startsWith('portrait:')) continue;
    const p = model.byId[pin.kortNoegle.slice('portrait:'.length)];
    if (!p || seen.has(p.id)) continue;
    seen.add(p.id);
    out.push(p);
  }
  for (const p of curatedFounders(model, n + out.length)) {
    if (out.length >= n) break;
    if (seen.has(p.id)) continue;
    seen.add(p.id);
    out.push(p);
  }
  return out.slice(0, n);
}
```

  `HomeView.tsx`: erstat `const curated = useMemo(() => (model ? curatedFounders(model, 4) :
  []), [model]);` (linje 51) med `forsideStartpersoner(model, feedPins, 4)` +
  `[model, feedPins]` — `feedPins`-staten findes allerede fra task 7 (intet ekstra
  netværkskald, spec §7.4).
- [ ] **Step 4: Kør — verificér PASS** + `npm run build`; manuelt: med en portræt-pin i
  kopi-basen viser "Redaktionen foreslår" den pinnede person først; uden pins er forsiden
  uændret.
- [ ] **Step 5: Commit** — `feat(feed): web-startpersoner fra portræt-pins med curatedFounders-fallback (skive 5)`.

---

## Task 13: Afstemning (skive 6)

**Files:**
- Modify: `docs/changelog.md`, `docs/README.md`, `docs/design/2026-07-18-levende-feed-koncept.md`.

- [ ] **Step 1: Ingen nye CI-jobs (spec §8)** — verificér blot at alle nye tests lander i
  suiter der allerede kører i `.github/workflows/ci.yml` (`feed` vitest, `web` vitest+build,
  `mobile` tsc+jest; `r`-jobbet er urørt — fase 3 har ingen R-flade). `db-verify.sql` køres
  manuelt mod kopi-basen (ingen base-service i CI, samme vilkår som fase 2).
- [ ] **Step 2: Fuld verifikation som slut-gate:** `packages/feed` `npx vitest run` +
  `npx tsc --noEmit`; `packages/core` `npx vitest run`; mobil `npx tsc --noEmit && npm test`;
  web `npm run test && npm run build` — alt grønt lokalt og i CI.
- [ ] **Step 3: Afstemning:** `docs/changelog.md`-implementeringspost (hvad er automatisk
  testet vs. manuelt verificeret — inkl. db-verify-asserts, fortryd-beviset og de manuelle
  UI-gennemløb fra task 8/10/11); `docs/README.md` indekserer fase 3-spec'en + statuslinje i
  design-sektionen; feed-konceptets §10 opdateres med fase 3-status og spec-link (som
  fase 1/2-linkene). `docs/database-current-state.md` røres IKKE — den opdateres først ved den
  gatede prod-migrering (Global Constraints).
- [ ] **Step 4: Commit** — `chore(feed): fase 3-afstemning — changelog, README, koncept-status (skive 6)`.

---

## Verifikation (afsluttende, spec §11)

- [ ] Migrationen idempotent (to kørsler af `db-migrations.sql` = én); db-verify grøn mod
  kopi-base med fase 2 anvendt: kladder/private/levende-subjekt-stories usynlige for anon OG
  authenticated, publiceret+afdød synlig, `story_kilde` cascader, `feed_pin` læsbar for anon,
  CHECK/UNIQUE/RPC-gates afviser, fortryd genskaber både status-skift og hel story.
  `get_advisors(security)` uden nye fund.
- [ ] Redaktøren kan — med dry-run-preview og versionshistorik — skrive en historie ud fra en
  hændelse (forudfyldt tekst/dato/kilder), publicere den og se den som `historie`-kort med
  kildefod; afpublicere fra styringssiden; pinne et kort til toppen og skjule et andet — og
  alle tre effekter slår igennem i klient-feed'en efter genindlæsning.
- [ ] Motor-beviserne (vitest): pin-blok først i input-orden, skjulte kort-id'er aldrig i
  output, historie dominerer statistisk (BASE 1,2 + nyPubliceret ×2), historie/arkiv/citat-
  dedup pr. hændelse, dinglende pins ufarlige — og **uden stories og pins er ordningen dybt
  identisk med fase 2** over de eksisterende fixtures.
- [ ] Web-forsidens startpersoner følger portræt-pins med `curatedFounders` som verificeret
  fallback (tom pin-liste ⇒ uændret forside).
- [ ] `tsc` + alle suiter grønne uden nye CI-jobs; ingen ændringer i evidens- eller
  hændelseslaget (diffen rører ingen eksisterende tabel-DDL — kun additivt skema + nye
  læsninger/skrivninger i det nye lag).

## Self-review-noter (udført ved skrivning)

- **Spec-dækning:** §3 → task 1; §4.1–4.3 → task 2+4; §4.4–4.5 → task 5; §5 → task 2–3+6–7;
  §6 → task 8; §7.1 → task 9; §7.2 → task 10; §7.3 → task 11; §7.4 → task 12; §8 → task 13.
  Alle spec-testkrav (§3.8, §4.5, §5.3, §7.4-testene) er fordelt på tasks.
- **Verificerede spec-formodninger:** `overrides`/`FeedOverride` er reelt ulæste (grep rammer
  kun `types.ts:61+72`); versionerings-asymmetrien mellem `schema.sql` (kun registry-række —
  loopet linje 1948-1957 laver triggeren) og `db-migrations.sql` (egen registry-INSERT +
  eksplicit trigger, fase 2-sektionen linje 2626-2635 som skabelon) er efterset i begge filer;
  webs mount-orkestrering bor i `FeedStreamView.tsx` og webs special-views (sammenlign/
  foraeldre-konflikter, `Redaktion.tsx:43-57 + 468-473`) er præcedensen for feed-styringssiden.
- **Bevidste implementer-verifikationer** (slå efter i koden frem for at gætte): PostgREST-
  omvendt nesting `story_kilde(…)` i task 10/11 (fallback: to flade queries); den præcise
  placering af mobil-forsidens `openCard`-pendant (task 8); om `web/src/data/__tests__/home.test.ts`
  allerede findes (task 12).
- **Bevidste plan-valg ud over spec'en:** (1) `red_rediger_story` bruger erstat-semantik (alle
  felter sendes hver gang) frem for delvis opdatering — deterministisk og komplet
  dry-run-preview; (2) `feedPins`-loadet bor i `HomeView` (ikke FeedStreamView) så forsiden og
  strømmen deler ét kald (spec §7.4's krav); (3) `sourceId` tilføjes additivt til
  hændelses-tidslinjens read-lag, fordi kilde-prefill ellers ikke kan bygge
  `red_set_story_kilder`-argumenter (spec §7.2 forudsatte at data var der — titel var, id ikke);
  (4) db-verify bruger sentinel-uuid som `skabt_af`/`oprettet_af` fordi kolonnernes
  `DEFAULT auth.uid()` er NULL for basens ejer; (5) terminal-`samle`-kortets tælling ændres
  ikke af skjul/pin (et skjult portræt tæller stadig som "vist person") — bevidst minimal-
  ændring; kan justeres senere hvis det opleves forkert.
- **Kendt afvigelse fra spec'ens skive-tabel:** `BASE.historie` tilføjes allerede i task 2
  (tsc-tvang fra `Record<FeedCard['kind'], number>`) — fuld scoring testes i task 4; samme
  manøvre som fase 2-planens `arkiv: 0.5`.





