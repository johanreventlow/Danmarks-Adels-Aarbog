# Levende feed — fase 3: minihistorier & redaktionel styring (design-spec)

**Dato:** 2026-07-19
**Styringsgrundlag:** `docs/design/2026-07-18-levende-feed-koncept.md` §3.2–3.4
(story-skemaet), §5 (kort-kataloget), §6 (web-forsiden), §7 (redaktionsflowet), §9
(privatlivs-invarianterne) + §10 (fase 3).
**Bygger direkte på:** fase 2-spec'en
(`2026-07-18-levende-feed-fase2-design.md`) — samme skive-struktur, samme DB-mønstre,
samme motor-disciplin. Fase 3 er additiv oven på et **uændret** evidens- OG hændelseslag.
**Implementeringsplan:** følger separat (task-for-task, TDD — som fase 1 og 2).
**Mål:** konceptets "løfte 3 — det kuraterede lag": redaktøren kan skrive korte
minihistorier (`story`) forankret i hændelser og kilder, publicere dem som feed'ens
flagskibs-kort (`historie`), og styre feed'en direkte via pin/skjul (`feed_pin`) — hvorved
`FeedOverride`-krogen fra v3-spec'en endelig realiseres. Web-forsidens startpersoner
udledes af pins. **LLM-assist er udtrykkeligt fase 4, ikke fase 3** — i fase 3 er alle
stories `oprindelse='redaktoer'`; skemaet bærer blot LLM-felterne som forward-kompat.

**Beslutninger arvet fra konceptet:** ✓a (formidlingslag — `story`/`feed_pin` konkurrerer
aldrig med påstand/konklusion), ✓d (arkivkort fortsat uden godkendelseskrav — stories
*opgraderer*, de gater ikke), ✓e (web-startpersoner fra pins, `curatedFounders` som
fallback), ✓f (intet LLM i denne fase). **Beslutninger truffet her:** (1) konceptskitsens
`gaelder_fra`/`gaelder_til` på `feed_pin` udgår (YAGNI — ingen konkret fase 3-brug; kan
tilføjes additivt senere); (2) `FeedOverride`-typen og det døde `overrides`-felt på
`FeedInputs` erstattes af en normaliseret `pins`-form (§4.4 — verificeret: `overrides`
læses ingen steder i motoren); (3) pin = **top-låst blok** allerøverst, med R1/R2
relakseret inde i blokken (redaktørens eksplicitte intention vinder over rytme); (4)
normal sletning af en story er **blød** (status `'arkiveret'`); `red_slet_story` er en
hård slet forbeholdt fejloprettelser (§3.6); (5) redaktionsfladerne er **asymmetriske**:
den dedikerede feed-styringsside bygges kun på web — mobil-appen er dev-only, ikke prod
(brugerbeslutning), og får kun inline pin/skjul-handlinger.

---

## 1. Baggrund & afgrænsning

I dag (empirisk, efter fase 2): feed'en er hændelses-drevet — `arkiv`-kort med verbatim
klausuler, klausul-drevne citater og hændelses-udvidede `paadennedag`-kort, alt fra den
rene motor i `packages/feed/src/`. Men det kuraterede lag mangler: `FeedOverride` er
stadig en no-op (`overrides?: FeedOverride[]` deklareres i `types.ts` men læses aldrig i
`order.ts` — koncept §1.4), web-forsidens startpersoner kommer fra
`curatedFounders`-heuristikken (`web/src/data/home.ts` siger selv "Der findes endnu ingen
redaktionel highlights-tabel"), og redaktøren kan markere hændelser
(`red_set_haendelse_status`) men hverken skrive formidlende tekst eller røre feed'ens
sammensætning direkte.

**I scope:** tre nye tabeller `story`/`story_kilde`/`feed_pin` (additiv migration + vocab
+ RLS + syv nye RPC'er + fuld versionering); `historie`-kortet + realiseret pin/skjul i
`@daa/feed`; klient-load af publicerede stories og pins i begge apps; kort-views;
story-editor i begge apps + dedikeret feed-styringsside kun på web; web-startpersoner fra
portræt-pins.

**Ikke i scope (fase 4, jf. koncept §10):** LLM-assist ("Foreslå historie"-knappen, Edge
Functions, batch-kladder — koncept §3.3/§8); hændelses-gruppering på tværs af udgaver
(○b); push. Feed'ens historie-kort dækker i fase 3 kun **person**-subjekter — tabellen er
polymorf klar til family/estate/lineage, men motoren og loaderne filtrerer på
`subjekt_type='person'` (samme v1-afgrænsning som hændelses-loadet). Prod-migrering er
out of scope (gated, fase 4-runbook-disciplinen) — se §2 om sekventeringen mod fase 2's
egen udestående prod-migration.

**Invariant-afstemning (invariant #4 + #1) — og fasens vigtigste forskel fra fase 2:**
`story` og `feed_pin` er ligesom `haendelse` **formidlingslag** (som
`person.visning_*`-cachen) og konkurrerer aldrig med påstand/konklusion — men hvor
`haendelse` er en *regenererbar projektion* af prosaen, er `story` og `feed_pin` **ægte
redaktionelt indhold**: originaltekst og kuraterings-afgørelser der ikke kan genskabes af
noget pass. Konsekvensen trækkes hele vejen: de versioneres på de *rigtige* kolonner
(titel/tekst/status/datoer/…) med minimal/ingen `skip_cols` — modsat `haendelse`, der kun
versionerer `feed_status` og skip'er alt andet (fase 2-spec §3.5). En story er heller
ikke et `narrative` (ordret kildeprosa) eller en `note` (internt redskab) — egen tabel er
ærligst (koncept §3.2). Evidenstabellerne røres ikke; `haendelse`-tabellen røres ikke.

---

## 2. Skæring (6 skiver)

| # | Skive | Nye/ændrede filer | Grænse/test |
|---|---|---|---|
| 1 | DB: `story` + `story_kilde` + `feed_pin` + vocab + RLS + 7 RPC'er + versionering | `schema.sql`, `db-migrations.sql`, `db-rls.sql`, `db-verify.sql` | idempotent migration; db-verify-asserts (synlighed, CHECK, RPC-gates, fortryd) |
| 2 | Motor: `historie`-kort + pins/hides i ordningen | `packages/feed/src/{types,score,pool,order,index}.ts`, ny `story.ts` + `pins.ts` (motor-delen) | vitest; **regressions-invariant: uden stories+pins ⇒ dybt identisk med fase 2** |
| 3 | Klient-load | `packages/feed/src/story.ts` (ren join), app-loadere `web/src/data/{story,feedPins}.ts` + `mobile/src/data/{story,feedPins}.ts` + `load.ts`/`useStore.ts`/`FeedStreamView.tsx`-integration | vitest/jest på ren join; tolerant load (fejl ⇒ tom, degraderer til fase 2) |
| 4 | Kort-views | `web/src/components/feed/FeedCardView.tsx`, `mobile/src/components/feed/FeedCardView.tsx` | manuel verifikation mod kopi-base med seedede stories (JSX unit-testes ikke — fase 1/2-præcedens) |
| 5 | Redaktion: write-lag + story-editor (begge apps) + feed-styringsside (kun web) + startpersoner | `mobile/src/data/redaktionWrite.ts`, `web/src/data/redaktionWrite.ts`, editor-flader, `web/src/Redaktion.tsx`, `web/src/data/home.ts` | jest/vitest på `buildRpcCall` + startperson-helper; dry-run-preview |
| 6 | CI + afstemning | `docs/changelog.md`, `docs/README.md` (CI-jobs genbruges — §8) | fuld suite grøn |

1 er forudsætning for 3 og 5 (mod rigtig base); 2 kan bygges parallelt med 1 (motoren er
netværksfri og testes mod fixtures); 3 er forudsætning for 4; 6 sidst. Hver skive holder
`tsc` + alle eksisterende suiter grønne — klientlagene degraderer tolerant mod en base
uden migrationen, så skiverne kan landes enkeltvis.

**Sekventering mod fase 2 (vigtig):** fase 2's egen prod-migration er endnu ikke udført
(koncept §10, status-noten). Kopi-basen der bruges til fase 3's db-verify og manuelle
verifikation skal derfor have **fase 2's migration anvendt først** — fase 3's
db-verify-blok forudsætter `haendelse`-tabellen (ankre, seeds) og
`entitet_offentlig`/`current_rolle` fra det eksisterende RLS-lag. Prod får de to
migrationer i rækkefølge (2 før 3) når den gatede deploy-procedure engang køres; intet i
fase 3 kortslutter den disciplin.

---

## 3. Skive 1 — DB: `story`, `story_kilde`, `feed_pin`

Alle tre tabeller følger fase 2's mønster-katalog (fase 2-plan Task 1 er den operative
skabelon): surrogat-BIGINT-PK uden IDENTITY (basens `max(id)+1`/`nid()`-mønster), dansk
kommentarstil med invariant-referencer, idempotent spejl i `db-migrations.sql` som ny
dateret sektion, og **to versionerings-mekanismer pr. fil** (§3.7).

### 3.1 `story` (`schema.sql` + idempotent spejl i `db-migrations.sql`)

```sql
-- FORMIDLINGSLAG (feed-koncept §3.2): redaktionel minihistorie. ÆGTE redaktionelt
-- indhold (modsat haendelse: IKKE en regenererbar projektion) — versioneres derfor
-- på de rigtige kolonner (fase3-spec §3.7). Bærer INGEN assertion/conclusion og
-- konkurrerer aldrig med evidenslaget; historien FORMIDLER, kilderne står i story_kilde.
CREATE TABLE IF NOT EXISTS story (
  id                  BIGINT PRIMARY KEY,
  subjekt_type        TEXT NOT NULL,       -- polymorf (fase 3-feed: kun 'person')
  subjekt_id          BIGINT NOT NULL,
  -- Ankre (alle valgfrie — en fri historie om subjektet er lovlig). ON DELETE SET NULL
  -- hele vejen: en story er redaktionelt indhold og skal OVERLEVE at dens anker
  -- forsvinder (fx en hændelse der regenereres væk af et forbedret pass).
  haendelse_id        BIGINT REFERENCES haendelse(id) ON DELETE SET NULL,
  fact_id             BIGINT REFERENCES fact(id) ON DELETE SET NULL,
  relation_id         BIGINT REFERENCES relation(id) ON DELETE SET NULL,
  historical_event_id BIGINT REFERENCES historical_event(id) ON DELETE SET NULL,
  titel               TEXT,                -- kort, valgfri
  tekst               TEXT NOT NULL,       -- ~40-90 ord redaktionel prosa (norm, ikke CHECK)
  date_min DATE, date_max DATE,            -- fuzzy dato — assertion-mønstret; kopieret fra
  date_qualifier TEXT,                     -- ankeret eller sat manuelt
  date_raw       TEXT,
  status          TEXT NOT NULL DEFAULT 'kladde'
                    CHECK (status IN ('kladde','klar','publiceret','arkiveret')),  -- vocab 'story_status'
  publiceret_dato DATE,                    -- sættes ved status→'publiceret' (RPC, §3.6);
                                           -- driver "nyligt publiceret"-boost (§4.2) mod
                                           -- injiceret todayISO — ALDRIG Date.now
  oprindelse      TEXT NOT NULL DEFAULT 'redaktoer'
                    CHECK (oprindelse IN ('redaktoer','llm_assisteret')),  -- vocab 'story_oprindelse'
  llm_model TEXT, llm_promptversion TEXT, llm_naar TIMESTAMPTZ,  -- forward-kompat fase 4 — ubrugte nu
  skabt_af      UUID NOT NULL DEFAULT auth.uid(),
  godkendt_af   UUID,
  godkendt_naar TIMESTAMPTZ,
  privat        BOOLEAN NOT NULL DEFAULT false
);
CREATE INDEX IF NOT EXISTS ix_story_subjekt   ON story(subjekt_type, subjekt_id);
CREATE INDEX IF NOT EXISTS ix_story_haendelse ON story(haendelse_id);
CREATE INDEX IF NOT EXISTS ix_story_status    ON story(status);
```

Konventions-afstemning: fuzzy dato genbruger assertion-felterne 1:1 (som `haendelse`);
`status`/`oprindelse` får DB-CHECK (små lukkede sæt, som `haendelse.feed_status`);
40–90-ords-længden er en redaktionel norm der håndhæves i editoren, ikke en
DB-constraint (prosa-længder er ikke skema-stof). `ON DELETE SET NULL` på alle fire ankre
er den bevidste modsætning til `haendelse.narrative_id ON DELETE CASCADE`: en projektion
dør med sit substrat, men redaktionelt indhold overlever sit anker (dinglende anker ⇒
historien står stadig, blot uden hændelses-kobling — kategorien på kortet bliver `null`,
§4.3).

### 3.2 `story_kilde`

```sql
-- Historien viser altid sine kilder (koncept §3.2 — "transparens er tonen"):
-- kortets diskrete fod "efter DAA 1939, s. 112". 1..n rækker pr. story.
CREATE TABLE IF NOT EXISTS story_kilde (
  id        BIGINT PRIMARY KEY,
  story_id  BIGINT NOT NULL REFERENCES story(id) ON DELETE CASCADE,
  source_id BIGINT NOT NULL REFERENCES source(id),
  side      TEXT
);
CREATE INDEX IF NOT EXISTS ix_story_kilde_story ON story_kilde(story_id);
```

`ON DELETE CASCADE` fra story: kildelisten er et rent vedhæng uden selvstændigt liv.
"1..n" håndhæves redaktionelt (editoren forudfylder fra ankerets narrativ-source, §7.2)
— ikke som DB-constraint, da en story-kladde lovligt kan stå uden kilder undervejs.

### 3.3 `feed_pin`

```sql
-- Redaktionel kurering af feed'en (koncept §7.5): pin (vis øverst) eller skjul et
-- KONKRET kort, adresseret ved dets stabile kort-id fra motoren ('portrait:<personId>',
-- 'story:<storyId>', 'arkiv:<haendelseId>', … — matcher FeedCard.id-formaterne i
-- packages/feed/src/pool.ts). En pin er ren kurering — "vis portrait:12 øverst" — og
-- bærer INGEN PII; derfor er tabellen offentligt læsbar (§3.5).
-- Konceptskitsens gaelder_fra/gaelder_til er bevidst udeladt (YAGNI — additivt senere).
CREATE TABLE IF NOT EXISTS feed_pin (
  id            BIGINT PRIMARY KEY,
  kort_noegle   TEXT NOT NULL UNIQUE,      -- én afgørelse pr. kort — pin OG skjul kan aldrig sameksistere
  handling      TEXT NOT NULL CHECK (handling IN ('pin','skjul')),
  oprettet_af   UUID NOT NULL DEFAULT auth.uid(),
  oprettet_naar TIMESTAMPTZ NOT NULL DEFAULT now()
);
```

`UNIQUE (kort_noegle)` er en designbeslutning, ikke kun integritet: den udelukker
strukturelt at samme kort både pinnes og skjules, så motoren aldrig skal vælge mellem
modstridende afgørelser. `handling`-sættet valideres af CHECK; der oprettes ingen ny
vocab-scheme for det (to koder, lukket sæt — som `person.koen`).

### 3.4 Vokabular (invariant #9, idempotent i `db-migrations.sql`)

```sql
INSERT INTO vocab (scheme, code, label) VALUES
  ('story_status','kladde',     'Under udarbejdelse — kun redaktion'),
  ('story_status','klar',       'Færdigskrevet, ikke publiceret'),
  ('story_status','publiceret', 'Synlig i feed for publikum'),
  ('story_status','arkiveret',  'Trukket tilbage — den normale slette-vej'),
  ('story_oprindelse','redaktoer',      'Redaktørskrevet'),
  ('story_oprindelse','llm_assisteret', 'LLM-kladde, menneskeligt godkendt (fase 4)')
ON CONFLICT (scheme, code) DO NOTHING;
```

`haendelse_kategori` genbruges uændret (historie-kortets kategori afledes af den
forankrede hændelse, §4.3 — ingen egen kategori-kolonne på `story`).

### 3.5 RLS (`db-rls.sql` — spejler hændelse-politikkerne, fase 2-spec §3.3)

```sql
-- story: publikum ser KUN publicerede, ikke-private historier om offentlige (afdøde,
-- ikke-private, ikke-stagede) subjekter — koncept §9.1-3. Kladder/klar/arkiveret når
-- aldrig publikum. authenticated fail-closer til samme regel som anon (F-02-linjen).
grant select on table public.story to anon, authenticated;
revoke insert, update, delete, references, trigger, truncate on table public.story from anon, authenticated;
alter table public.story enable row level security;
drop policy if exists anon_read on public.story;
create policy anon_read on public.story for select to anon
  using (status = 'publiceret'
     and coalesce(privat, false) = false
     and public.entitet_offentlig(subjekt_type, subjekt_id));
drop policy if exists auth_read on public.story;
create policy auth_read on public.story for select to authenticated
  using (status = 'publiceret'
     and coalesce(privat, false) = false
     and public.entitet_offentlig(subjekt_type, subjekt_id));
drop policy if exists redaktion_read on public.story;
create policy redaktion_read on public.story for select to authenticated
  using ((select public.current_rolle()) = 'redaktion');

-- story_kilde: arver parent-storyens synlighed (EXISTS-cascade — note→fact-mønstret).
-- (anon-/auth-politik: exists(select 1 from public.story s where s.id = story_id);
--  redaktion_read: current_rolle() = 'redaktion' — samme tre-blokke-form som story.)

-- feed_pin: LÆSBAR for alle (anon, authenticated, redaktion) — pin/skjul-effekten skal
-- nå klient-motoren, og en pin er ren kurering uden PII, så offentlig læsning er både
-- korrekt og nødvendig. Skrivning KUN via redaktions-RPC'erne.
grant select on table public.feed_pin to anon, authenticated;
revoke insert, update, delete, references, trigger, truncate on table public.feed_pin from anon, authenticated;
alter table public.feed_pin enable row level security;
drop policy if exists anon_read on public.feed_pin;
create policy anon_read on public.feed_pin for select to anon using (true);
drop policy if exists auth_read on public.feed_pin;
create policy auth_read on public.feed_pin for select to authenticated using (true);
```

De eksplicitte `revoke … from anon, authenticated` er obligatoriske for alle tre tabeller
— Supabases direkte default-grants gør `REVOKE FROM PUBLIC` utilstrækkeligt
(review 22-lektien, samme formulering som fase 2-spec §3.3). GDPR-arven (invariant #8):
`entitet_offentlig` fail-closer på levende/private/stagede subjekter, `privat`-flaget
respekteres oveni, og klienten filtrerer desuden som defense-in-depth (§5). Efter DDL
mod kopi-basen køres `get_advisors(security)` (etableret disciplin efter enhver
migration).

Bemærk hvad pin-politikken lækker: en pin på `'portrait:<personId>'` af et subjekt der
senere bliver privat, afslører højst at et kort-id engang fandtes — selve kortet
genereres ikke længere, og pin'en er da dinglende og inaktiv (§4.4). Redaktionen bør
rydde dinglende pins fra styringssiden (§7.3), men sikkerheden afhænger ikke af det.

### 3.6 RPC'er (eneste skrivevej — `red_set_haendelse_status`-mønstret)

Alle syv følger samme skelet: gate på `current_rolle() = 'redaktion'` → validér input →
`PERFORM begin_change_set(…)` → skriv. Dermed er dry-run/LIVE og versionshistorik gratis
via det eksisterende `submitChange`-flow (§7.1), og hvert kald er fortrydbart via
`red_fortryd_change_set`.

| RPC | Signatur (skitse) | Adfærd |
|---|---|---|
| `red_opret_story` | `(p_subjekt_type text, p_subjekt_id bigint, p_tekst text, p_titel text = null, p_haendelse_id bigint = null, p_fact_id bigint = null, p_relation_id bigint = null, p_historical_event_id bigint = null, p_date_min date = null, p_date_max date = null, p_date_qualifier text = null, p_date_raw text = null, p_privat boolean = false) RETURNS bigint` | Opretter som `'kladde'`, `oprindelse='redaktoer'` (hårdkodet i fase 3 — RPC'en tager ingen oprindelse-parameter); afviser tom `p_tekst`; returnerer nyt id |
| `red_rediger_story` | `(p_story_id bigint, …samme valgfrie felter…)` | Opdaterer titel/tekst/ankre/dato/privat; rører ikke status/publiceret_dato |
| `red_set_story_status` | `(p_story_id bigint, p_status text)` | Validerer mod de fire koder; afviser fail-closed overgang til `'publiceret'`, hvis historien endnu ikke har mindst én `story_kilde`; **hver gyldig overgang TIL `'publiceret'` sætter `publiceret_dato := current_date`**; overgange væk fra publiceret rører den ikke (historisk dato bevares — klienten viser alligevel kun `status='publiceret'`, så en bevaret dato lækker intet) |
| `red_slet_story` | `(p_story_id bigint)` | **Hård DELETE**, forbeholdt fejloprettelser — den normale slette-vej er `red_set_story_status(id,'arkiveret')`. Hård slet er forsvarlig netop fordi `story` fuldversioneres (§3.7): DELETE-eventet bærer hele rækken, og fortryd genskaber den (modsat `haendelse`, hvor DELETE-fortryd eksplicit er uunderstøttet). `story_kilde`-rækkerne cascader og genskabes IKKE af fortryd (de versioneres ikke, §3.7) — de gen-sættes via `red_set_story_kilder` |
| `red_set_story_kilder` | `(p_story_id bigint, p_kilder jsonb)` | Erstatter kildelisten (DELETE + INSERT) fra et jsonb-array af `{source_id, side?}`; validerer at hver source findes |
| `red_set_feed_pin` | `(p_kort_noegle text, p_handling text)` | Upsert `ON CONFLICT (kort_noegle) DO UPDATE` (handling + oprettet_af/naar); validerer `p_handling IN ('pin','skjul')` og ikke-tom nøgle. Nøglens *format* valideres ikke — en nøgle uden modsvarende kort er blot en dinglende, inaktiv afgørelse (§4.4) |
| `red_fjern_feed_pin` | `(p_kort_noegle text)` | DELETE; fejler hvis nøglen ikke findes (som `red_set_haendelse_status` fejler på ukendt id) |

Skitse af skelettet (spejler `red_set_haendelse_status`, fase 2-spec §3.4 — resten
skrives analogt ved implementering):

```sql
CREATE OR REPLACE FUNCTION red_set_story_status(p_story_id bigint, p_status text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_stype text; v_sid bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF p_status NOT IN ('kladde','klar','publiceret','arkiveret') THEN
    RAISE EXCEPTION '''%'' er ikke en gyldig story-status', p_status;
  END IF;
  SELECT subjekt_type, subjekt_id INTO v_stype, v_sid FROM story WHERE id = p_story_id;
  IF v_stype IS NULL THEN RAISE EXCEPTION 'Story % findes ikke', p_story_id; END IF;
  PERFORM begin_change_set('red_set_story_status',
    format('Satte status %s på story %s', p_status, p_story_id), v_stype, v_sid);
  UPDATE story SET status = p_status,
    publiceret_dato = CASE WHEN p_status = 'publiceret' THEN current_date ELSE publiceret_dato END
  WHERE id = p_story_id;
END $$;
```

Grants: db-rls.sql's generiske `red\_%`-loop fanger alle syv ved gen-anvendelse, men da
`db-migrations.sql` ikke gen-anvender RLS-laget (fase 4-runbook-lektien), skal
migrationssektionen **selv** indeholde `GRANT EXECUTE … TO authenticated` for hver af de
syv (præcis som fase 2's migration gjorde for `red_set_haendelse_status`).

### 3.7 Versionering — fuld, modsat `haendelse`

`story` og `feed_pin` registreres i `version_pk_registry` med **ingen** `skip_cols` —
alle kolonner logges, fordi indholdet er redaktionelt og uerstatteligt (§1). Det er den
bevidste kontrast til `haendelse`-rækken, hvor alle projektionskolonner er skip_cols og
kun `feed_status` logges:

```sql
INSERT INTO version_pk_registry (tabel, pk_cols, skip_cols) VALUES
  ('story',    ARRAY['id'], ARRAY[]::text[]),
  ('feed_pin', ARRAY['id'], ARRAY[]::text[])
ON CONFLICT (tabel) DO UPDATE SET pk_cols=excluded.pk_cols, skip_cols=excluded.skip_cols;
```

`story_kilde` versioneres **ikke** (holdes ude af registry): kildelisten er et vedhæng
med erstat-semantik — `red_set_story_kilder` kan altid gen-sætte den, og at logge
DELETE+INSERT-par for hver liste-erstatning ville støje historikken uden at beskytte
noget uerstatteligt. Begrænsningen dokumenteres: fortryd af et
`red_set_story_kilder`-/`red_slet_story`-kald genskaber ikke kildelisten.

**To mekanismer pr. fil** (fase 2-plan Task 1 er den verificerede skabelon — samme
asymmetri gælder her): i `schema.sql` tilføjes de to rækker til den **eksisterende**
`VALUES`-liste i `version_pk_registry`-INSERT'en, hvorefter filens generiske
trigger-tilknytnings-loop (`DO $$ … FOR r IN SELECT tabel FROM version_pk_registry LOOP …`)
selv opretter `trg_log_story`/`trg_log_feed_pin` — **ingen** separat `CREATE TRIGGER`
skrives dér. I `db-migrations.sql` er situationen omvendt: filens loop har allerede kørt
når den nye daterede sektion appendes, så sektionen skal selv indeholde både sin egen
`INSERT … ON CONFLICT (tabel) DO UPDATE`-registrering OG eksplicitte
`CREATE TRIGGER trg_log_story … EXECUTE FUNCTION log_change()` (og tilsvarende for
`feed_pin`).

### 3.8 `db-verify.sql`-asserts (kør mod kopi-base med fase 2 anvendt)

Nyt `DO $$ … END $$;`-blok i den etablerede stil (negative sentinel-id'er i et ubrugt
bånd; `SET LOCAL ROLE anon; … RESET ROLE;`; afsluttende `RAISE NOTICE 'OK: …'`):

- `to_regclass` for alle tre tabeller er ikke-NULL.
- CHECK afviser: `story.status='udgivet'`, `story.oprindelse='ai'`,
  `feed_pin.handling='fremhaev'` (forvent `check_violation`).
- `feed_pin`: UNIQUE afviser anden række med samme `kort_noegle`; **anon kan læse** en
  seedet pin (1 række).
- `story`-synlighed som anon: publiceret + afdødt/offentligt subjekt ⇒ 1 række;
  `status='kladde'` ⇒ 0; publiceret men **levende** subjekt ⇒ 0; publiceret men
  `privat=true` ⇒ 0. `story_kilde` følger med (cascade: kladde-storyens kilde er
  usynlig). Samme asserts gentages som authenticated for publiceret+kladde (F-02-linjen).
- RPC-gates: `red_opret_story` og `red_set_feed_pin` afvises uden redaktion-rolle
  (EXCEPTION); ugyldig status/handling afvises.
- **Fortryd-assert:** som redaktion — opret story via `red_opret_story`, publicér via
  `red_set_story_status`, kald `red_fortryd_change_set` på status-settet ⇒ storyen er
  tilbage på `'kladde'`; fortryd derefter opret-settet ⇒ storyen er væk (fuld
  versionering uden skip_cols gør begge retninger mulige — det er netop pointen i §3.7).

---

## 4. Skive 2 — motoren: `historie`-kortet + realiserede pins/hides

Motoren forbliver en ren funktion — ingen netværk, ingen `Date.now`, ingen
`Math.random`. Al ny dynamik kommer fra to nye injicerede inputs (`storieBy`, `pins`) og
det allerede injicerede `todayISO`.

### 4.1 Typer (`types.ts`)

Ny variant i `FeedCard`-unionen (feltformen følger `arkiv`-kortets mønster):

```ts
| { kind: 'historie'; id: string; personId: string; titel: string | null; tekst: string;
    aarLabel: string | null; kategori: string | null; kilde: string | null;
    nyPubliceret?: boolean; kicker: string }
```

`id = 'story:' + <storyId>` (kort-id-formatet fra koncept §3.4 — samme byggestils-familie
som `'portrait:'+p.id` / `'arkiv:'+item.id` i `pool.ts`). `kicker: 'Historie'`.
Kortet er bogmærkbart gratis: `bookmarkPersonId` bruger `'personId' in card`
(eksisterende kontrakt, uændret). `nyPubliceret` er et valgfrit build-tids-flag efter
præcis samme mønster som `jubilaeum.paaDagen` og `arkiv.interessant` — se §4.2 for
hvorfor datoen ikke bæres rå på kortet.

`FeedInputs` udvides, og den døde krog fjernes:

```ts
export type FeedPinInput = { kortNoegle: string; handling: 'pin' | 'skjul' };

export interface FeedInputs {
  …eksisterende felter…
  storieBy?: StorieBy;          // udeladt ⇒ fase 2-adfærd (som haendelserBy/livsdatoBy)
  pins?: FeedPinInput[];        // normaliseret, KLIENT-sorteret (§4.4) — erstatter overrides
}
```

**Valget om `FeedOverride`:** typen (`{ pin?: string[]; hide?: string[] }`) og feltet
`overrides?: FeedOverride[]` slettes og erstattes af den flade `FeedPinInput`-form.
Begrundelse: (a) verificeret dødt — `overrides` deklareres i `types.ts` men læses ingen
steder i motoren eller apps, så fjernelsen er ikke-brydende inden for workspacet; (b) den
flade form spejler `feed_pin`-rækkerne 1:1 (én afgørelse pr. nøgle, ingen
flet-semantik over flere override-objekter at definere); (c) rækkefølgen af pins er
semantisk bærende (pin-blokkens orden), hvilket et `pin: string[]`-felt i et array af
overrides ville gøre tvetydigt.

`paadennedag`-varianten er allerede udvidet i fase 2 og røres ikke.

### 4.2 Scoring (`score.ts`)

- **`BASE.historie = 1.2`** — en ny flagskibs-tier OVER alle auto-kort (portræt/
  paadennedag/dagensperson ligger på 1.0). Begrundelse: det redaktionelle lag skal
  dominere når det findes (koncept §4.1: "story-kort over auto-kort") — en håndskrevet
  minihistorie er pr. definition bedre feed-stof end den auto-genererede projektion af
  samme stof. Tilføjelsen til `BASE`-recorden er obligatorisk for at kompilere
  (`Record<FeedCard['kind'], number>` — udeladelse er en `tsc`-fejl, hvilket er værnet
  mod at glemme det).
- **"Nyligt publiceret"-boost:** `if (card.kind === 'historie' && card.nyPubliceret) s *= 2`
  — ægte "nyt i arkivet" (koncept §9.5: aldrig fabrikerede tidsstempler; boostet hviler
  på den ægte `publiceret_dato`). Flaget beregnes i `buildStorieKort` (§4.3) som
  `publiceret_dato` inden for **30 dage** før det injicerede `todayISO`. Valget om at
  bære et **færdigberegnet boolean på kortet** frem for rå dato + `todayISO` i
  score-konteksten følger den etablerede præcedens: `buildJubilaeer` modtager `todayISO`
  og sætter `paaDagen`, hvorefter `score()` kun læser flaget — én dato-sammenligning ét
  sted, og `ScoreContext` forbliver uændret.
- Bogmærke- (×1,5) og seen-signalerne gælder automatisk (historie-kortet har `personId`
  og `id` som alle andre).

### 4.3 `buildStorieKort` (ny `packages/feed/src/story.ts`, motor-delen)

```ts
export function buildStorieKort(
  model: Model,
  storieBy: StorieBy,
  haendelserBy: HaendelserBy,
  todayISO: string,
): { cards: FeedCard[]; usedHaendelseIds: Set<string> };
```

- Én kandidat pr. publiceret story (klient-loadet leverer kun publicerede, §5) hvis
  personen findes i `model.byId` — ikke-kanoniseret/ukendt id ⇒ kortet udelades tavst
  (samme regel som `buildArkivKort`). Stabil `byIdStr`-sortering som alle builders.
- `aarLabel`: `dateRaw` foretrukket (verbatim), ellers årstal af `dato.min`, ellers
  `null` — ordret `arkiv`-kortets regel (aldrig fabrikeret præcision).
- `kategori`: opslag af storyens `haendelseId` i personens `haendelserBy`-liste — findes
  den forankrede hændelse, arves dens kategori; intet anker eller hændelsen ikke længere
  i klient-settet ⇒ `null`. (Derfor tager builderen `haendelserBy` som parameter — den er
  allerede i `FeedInputs`, så intet nyt input opfindes.)
- `nyPubliceret`: sat når `publiceretDato` ligger inden for 30 dage før `todayISO`
  (streng-dato-aritmetik på injiceret dato — motoren rører aldrig klokken).
- **Dedup-trådning (fasens `usedCitatHaendelseIds`-pendant):** hver publiceret story med
  `haendelseId` lægger dét id i `usedHaendelseIds`. I `buildFeedOrder` kaldes
  `buildStorieKort` **først**, og sættet trådes videre: (a) ind i `buildPortraitAndCitat`
  som ny valgfri parameter (default tomt sæt — bagudkompatibel), hvor citat-kandidaterne
  filtreres mod det, og (b) ind i `buildArkivKort`s eksklusion som union med
  `usedCitatHaendelseIds`. Effekt: en hændelse med en publiceret historie optræder
  **aldrig** samtidig som `historie`- OG `arkiv`-/`citat`-kort — historien er
  opgraderingen (koncept §5: "stories opgraderer gradvist de bedste hændelser").

### 4.4 Pins/hides i `buildFeedOrder` (`order.ts`) — `FeedOverride`-krogen realiseres

Normaliseringen sker i klienten (§5.1/§5.2): motoren modtager `pins` som en
færdig-sorteret liste og forbliver ren. Inde i `buildFeedOrder`:

**Skjul (`handling: 'skjul'`):** kort hvis `card.id` er i skjul-sættet filtreres **helt
ud af `candidateCards` før scoring** — de kan hverken trækkes, låses eller tvinges ind af
R3. To skjul-stier sameksisterer herefter bevidst og **ortogonalt**:
`haendelse.feed_status='skjult'` (fase 2) virker pr. *hændelse* og håndhæves allerede i
RLS + klient-join, så hændelsen når aldrig motoren i nogen kort-form (arkiv, citat,
paadennedag); `feed_pin` med `'skjul'` (fase 3) virker pr. *kort-id* og kan ramme
vilkårlige korttyper (et bestemt portræt, et gods-kort, en enkelt arkiv-flavor af en
hændelse der gerne må beholde sine andre flavors). Den første er indholds-dom, den anden
er kurering — ingen af dem erstatter den anden, og de dokumenteres side om side i
`order.ts`-kommentaren.

**Pin (`handling: 'pin'`) = top-låst blok:** pinnede kort — dem hvis `card.id` matcher en
pin-nøgle OG som stadig genereres som kandidat — trækkes ud af kandidatmængden og
placeres som en fast blok **allerøverst**, før alle andre positionsmekanismer:

- Udtrækket sker **før** `score > 0`-filteret: en pin vises uanset set-hukommelse
  (`seenWeights=0` udelukker normalt et kort helt, men redaktørens eksplicitte pin
  vinder — den modsatte eksplicitte handling, skjul, findes til at fjerne).
- **Rækkefølge i blokken:** `pins`-arrayets orden, som klienten har sorteret
  deterministisk på `feed_pin.oprettet_naar` stigende med `kort_noegle` som tiebreak
  (§5.1). Valget "klienten sorterer, motoren bevarer" holder motoren fri for
  tidsstempel-viden og gør blok-ordenen til ren input-orden — ældste pin øverst betyder
  at en etableret forside ikke hopper rundt når der tilføjes nye pins nederst i blokken.
- **R1/R2 relakseres inde i blokken** (bevidst): kortene pushes direkte uden
  `chooseRankedIndex` — to portrætter i træk er lovligt når redaktøren har bedt om
  præcis dem. Rytmen genoptages naturligt EFTER blokken, for de eksisterende regler
  læser den faktiske `ordered`-liste: første frie træk ser blokkens sidste kort som
  `prevKind`, blokkens personer i R2-vinduet og blokken i R3-lookbacket — pin-indholdet
  tæller altså med i rytmen udadtil, det fritages kun indbyrdes.
- **Komposition med positionslåsene (offsets):** med `P = blokkens længde` forskydes de
  eksisterende låse tilsvarende ned — dagensperson-låsen trækkes i `[P .. P+2]` og
  slægt-låsen i `[P+3 .. P+9]` (i dag `[0..2]` hhv. `[3..9]`), med samme
  clamping/kollisions-regler som i dag; `totalBeforeTerminal` medregner blokken.
  Selve while-løkken er uændret — `ordered` forudfyldes blot med blokken før den starter.
  Er et af de låste kort selv pinnet (dagens persons portræt findes ikke som kandidat,
  men fx dagensperson-kortet selv kan pinnes), er det allerede taget ud som pin,
  `takeLocked` finder intet, og låsen udgår tavst — pin vinder.
- **Ingen ekstra RNG-forbrug:** pin-udtræk og blok-placering kalder aldrig `rng()`.
  Positions-lodtrækningerne konsumerer nøjagtig samme antal kald som i dag. Det er
  forudsætningen for regressions-invarianten nedenfor.

**Dinglende pins/hides:** en `kort_noegle` uden modsvarende genereret kort (skjult story
afpubliceret, hændelse regenereret væk, person blevet privat) ignoreres tavst — aldrig
crash, aldrig et tomt pladsholder-kort. Symmetrisk: et skjul mod et kort der ikke længere
genereres er en no-op.

### 4.5 Regressions-invariant + test (vitest)

**REGRESSIONS-INVARIANT (fasens disciplin — spejler fase 2's tomme-`haendelserBy`-test):**
`buildFeedOrder` uden publicerede stories (`storieBy` tom/udeladt) OG med tomme
pins/hides (`pins` tom/udeladt) producerer **dybt identisk** output med fase 2, over de
eksisterende `order.test.ts`-fixtures. Dette testes eksplicit og er den vigtigste
enkelt-test i skiven: den beviser at hele fase 3-laget er strengt additivt i motoren.

Øvrige tests:

- Determinisme: samme inputs (inkl. `storieBy` + `pins`) → identisk ordning.
- `buildStorieKort`: aarLabel-reglerne; kategori-arv fra forankret hændelse (og `null`
  uden anker); `nyPubliceret`-grænsen (dag 30 inde, dag 31 ude — mod injiceret
  `todayISO`); ukendt person udelades; `usedHaendelseIds` indeholder netop de forankrede.
- Dedup: hændelse med publiceret story optræder aldrig som arkiv- eller citat-kort
  (begge stier testes); hændelser uden story er upåvirkede.
- Scoring: `BASE.historie` over portræt (property-test som fase 1's bookmark-test:
  historie-kort ligger statistisk tidligere over en fast seed-liste); `nyPubliceret`
  fordobler.
- Pins: pin-blok står først og i input-orden; blok med to ens kinds i træk er lovlig
  (R1-relaksering); dagensperson-/slægt-lås forskudt korrekt ved P>0; pin overlever
  `seenWeights=0`; skjult kort-id findes aldrig i output; dinglende pin/skjul ⇒ ingen
  crash, output som uden dem; pin+skjul på samme nøgle er umulig pr. input-kontrakt
  (UNIQUE i DB — motoren behøver ingen konfliktregel, men en defensiv test dokumenterer
  at skjul filtreres før pin-udtræk, så en ugyldig dobbelt-input degraderer til skjul).
- Strøm-API'et er uberørt (ordningen doseres som hidtil) — én test at
  `createFeedStream` leverer pin-blokken i første side.

---

## 5. Skive 3 — klient-load (spejler hændelses-loadet 1:1)

### 5.1 Ren join i `@daa/feed` (`packages/feed/src/story.ts` + `pins.ts`)

Spejler `buildHaendelserBy`-kontrakten (`haendelser.ts`: rå PostgREST-rækker ind,
kanoniseret opslag ud; intet netværk i pakken):

```ts
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

export interface StoryItem {
  id: string;                       // story.id som streng ('story:'+id er kort-id'et)
  titel: string | null;
  tekst: string;
  dato: FuzzyDato;
  dateRaw: string | null;
  haendelseId: string | null;       // dedup-ankeret (§4.3)
  publiceretDato: string | null;    // driver nyPubliceret-flaget i buildStorieKort
  kilde: string | null;             // 'DAA 1939, s. 112' — flere kilder joines med ' · '
}
export type StorieBy = Record<string, StoryItem[]>;   // kanonisk person-id → id-sorteret

export function buildStorieBy(
  rows: StoryRow[],
  kilder: StoryKildeRow[],
  sources: StorySourceRow[],
  canonicalIdById: Record<string, string> = {},
): StorieBy;
```

Kanonisering via `canonicalIdById[String(subjekt_id)] ?? String(subjekt_id)`;
kilde-strengen sammensættes pr. kilde som hændelses-loadets `'DAA <udgave>, s. <side>'`
(source uden udgave ⇒ kilden udelades; ingen kilder ⇒ `kilde: null`), flere kilder
joines deterministisk (kilde-rækkernes `id`-orden) med `' · '` — visningens "efter …"-
præfiks er view-lagets sag (§6). Defensivt filter: `status !== 'publiceret'` og
`privat === true` springes over selv om både RLS og queryen allerede fjerner dem
(defense-in-depth, koncept §9.2). Sortering pr. person: `id`-tiebreak (stabil
`byIdStr`-disciplin).

Pin-normaliseringen bor i sin egen lille fil `packages/feed/src/pins.ts` (pins vedrører
alle korttyper, ikke stories — derfor ikke i `story.ts`):

```ts
export interface FeedPinRow { kort_noegle: string; handling: string; oprettet_naar: string | null; }
export function buildFeedPins(rows: FeedPinRow[]): FeedPinInput[];
```

`buildFeedPins` filtrerer ukendte handlinger defensivt og sorterer deterministisk på
`oprettet_naar` stigende (NULL sidst) med `kort_noegle` som tiebreak — det er hele
"klienten sorterer, motoren bevarer"-kontrakten fra §4.4. Begge filer eksporteres fra
`index.ts`.

### 5.2 App-loadere (spejlpar af hændelses-loaderne)

`web/src/data/story.ts` + `mobile/src/data/story.ts` og `web/src/data/feedPins.ts` +
`mobile/src/data/feedPins.ts` — samme form som `haendelser.ts`-parret: `getAll` +
`IN_CHUNK=200`-chunking, tolerant top-catch ⇒ tomt resultat +
`console.warn('[story] utilgængelig — historie-kort udelades')` hhv.
`'[feedPins] utilgængelig — feed vises ukurateret'` — feed'en brydes aldrig; mod en base
uden migrationen degraderer alt til fase 2-adfærd.

- Story-query 1: `sb.from('story').select('id,subjekt_id,haendelse_id,titel,tekst,date_min,date_max,date_qualifier,date_raw,status,publiceret_dato,privat').eq('subjekt_type','person').eq('status','publiceret').order('id')`
  (status-filteret er payload-hygiejne og defense-in-depth — RLS håndhæver alligevel).
- Query 2/3: `story_kilde`-rækker via chunked `.in('story_id', …)`, derefter `source`
  (`id,udgave`) via chunked `.in('id', …)` på de refererede source-id'er — nøjagtig
  hændelses-loaderens tre-trins-form.
- Pin-query: `sb.from('feed_pin').select('kort_noegle,handling,oprettet_naar').order('oprettet_naar').order('kort_noegle')` → `buildFeedPins`.

**Mobil-integration** (`load.ts` + `useStore.ts` — hændelses-skabelonen): to nye
parallelle promises ved siden af det eksisterende `haendelseRowsP`-mønster i `load()`;
join efter collapse med `collapsed.canonicalIdById`; nye `LoadResult`-/store-felter
`storieBy: StorieBy` og `feedPins: FeedPinInput[]`; `{}`/`[]` i SEED-fallbacken
(offline-seedet bærer hverken stories eller pins — kortene udelades, feed'en er
ukurateret). Felterne føres ind i feed-strømmens `FeedInputs`.

**Web-integration** (`FeedStreamView.tsx` — samme mount-orkestrering som
hændelses-loaderen): to nye state-hooks efter `haendelserBy`-mønstret (effekt ved mount,
`alive`-guard, sæt state ved ankomst), og begge føjes til strøm-genopbygningens
dependency-liste, så strømmen genopbygges med samme seed og genoptages via
`resumeStream` når data ankommer (append-kontrakten fra fase 1 — allerede viste kort
røres ikke).

### 5.3 Test

Vitest (`packages/feed`): `buildStorieBy` (join, kanonisering, kilde-sammensætning én/
flere/ingen kilder, defensive filtre, sortering, tomme input ⇒ `{}`); `buildFeedPins`
(sortering, NULL-tidsstempel, ukendt handling filtreres). App-lag: mockede queries (fejl
⇒ tom + warn), chunking, status-filter i queryen — spejl af hændelses-loader-testene i
begge apps.

---

## 6. Skive 4 — kort-views (web + mobil)

Ny `case 'historie'` i begge `FeedCardView.tsx` (webs switch har allerede
`'portrait'`-til-`'samle'`-casene; mobilens spejl ditto): flagskibs-styling i
redaktionel ro — kicker, titel (kun når sat), brødteksten som kortets krop, dato-label
(`aarLabel`), kategori diskret (som arkiv-kortet) og kildefoden `«efter {kilde}»`
("efter DAA 1939, s. 112" — "efter"-præfikset lever her i view-laget, jf. §5.1).
`nyPubliceret` må gerne vises som en diskret "Nyt i arkivet"-markør — det er ærligt
(ægte publiceringsdato, koncept §9.5). Ingen AI-oprindelses-visning (moot i fase 3 —
§12).

Kun tokens fra `mobile/src/theme/tokens.ts` hhv. `web/src/theme.ts` — ingen nye
farver/fonte. Navigation: hele kortet navigerer til personen, som portræt-kortet gør det
i hver app. Ren JSX unit-testes ikke (fase 1/2-præcedens); verificeres manuelt i
browser/simulator mod kopi-basen med seedede stories (skive 1's verify-seeds kan
genbruges som udgangspunkt), og det dokumenteres hvad der er testet vs. manuelt
verificeret.

---

## 7. Skive 5 — redaktion (asymmetrisk web/mobil)

Asymmetrien er en brugerbeslutning med klar begrundelse: mobil-appen er dev-only (kører
kun på brugerens egen enhed), web er prod. Den *lette* inline-redigering bygges derfor på
begge apps (den bor alligevel i person-redaktionen, som findes begge steder), mens den
*dedikerede* feed-styringsside kun bygges på web.

### 7.1 Write-lag (begge apps — ren + testbar)

`Change`-unionen og `buildRpcCall` udvides i begge apps' `redaktionWrite.ts` (fortsat
spejlpar — delt-pakke-ekstraktion er en kendt follow-up, jf. filernes egne kommentarer).
`haendelseStatus`-caset er den direkte præcedens: validér felterne, returnér
`{ fn, args }`, ellers `null`.

```ts
| 'opretStory' | 'redigerStory' | 'setStoryStatus' | 'sletStory' | 'setStoryKilder'
| 'setFeedPin' | 'fjernFeedPin'
```

Nye valgfrie felter på `Change`: `storyId?: number`;
`storyStatus?: 'kladde' | 'klar' | 'publiceret' | 'arkiveret'`; `kortNoegle?: string`;
`handling?: 'pin' | 'skjul'`; `kilder?: { sourceId: number; side?: string }[]`;
story-feltværdierne (titel/tekst/ankre/dato/privat) via det eksisterende
`payload`-felt. Mapningen er 1:1 til §3.6-RPC'erne
(`opretStory → red_opret_story`, … `fjernFeedPin → red_fjern_feed_pin`), med samme
fail-closed validering som `haendelseStatus` (manglende/ugyldige felter ⇒ `null`).

Dermed er **dry-run/LIVE gratis**: `submitChange(change, { dryRun })` viser det
planlagte kald i preview uden at røre basen, og webs `planCall`-rolle-routing degraderer
ikke-redaktører til `red_suggest`-staging uændret. Test: nye `buildRpcCall`-cases i
begge apps' eksisterende suiter (gyldige mapninger + fail-closed-afvisninger).

### 7.2 Story-editor (begge apps)

"Ny historie"-handling ud for en hændelse i den **eksisterende** hændelses-tidslinje fra
fase 2 (webs tidslinje-sektion i `Redaktion.tsx`s person-editor; mobilens
`HaendelseTidslinje`-komponent — begge får en knap pr. hændelses-post). Handlingen åbner
editoren forudfyldt fra ankeret:

- `titel` tom; `tekst` forudfyldt med hændelsens klausul som råmateriale (redaktøren
  omskriver til de ~40–90 ord — klausulen er startpunkt, ikke facit);
- dato-felterne kopieret fra hændelsens `date_min/max/qualifier/raw`;
- kilder forudfyldt fra hændelsens narrativ-source (+side) — de data er allerede i
  redaktions-readlaget fra fase 2 (`sourceTitel`/`side` på tidslinje-posterne).

Editoren kan også åbnes på en eksisterende story (redigér) og bærer status-piller
(kladde / klar / publiceret / arkiveret) i det etablerede pille-mønster fra fase 2's
statusvælger — klik sender `setStoryStatus` gennem det normale dry-run/LIVE-flow.
Arkivér-pillen ER den normale sletning (§3.6); hård slet eksponeres ikke i UI'et i
fase 3 (fejloprettelser håndteres via psql/RPC direkte). Kilde-listen redigeres som en
simpel liste (tilføj/fjern source + side) der sendes samlet via `setStoryKilder`
(erstat-semantik).

Redaktions-read: person-editorens flade henter subjektets stories i **alle** statusser
(redaktion_read-politikken) via en lille ren mapper i `redaktionRead.ts` efter
`mapHaendelser`-mønstret — fejl kaster (aldrig tavs catch i redaktionen, fase 2-reglen).

### 7.3 Feed-styringsside — kun web

En selvstændig redaktions-flade i `web/src/Redaktion.tsx` (egen sektion/visning ved
siden af person-editoren — implementer verificerer selv hvor Redaktions-navigationen
komponeres og spejler den; webbens hash-routing i `router.ts` er rammen). Konceptets §7
sætter tonen: **"kurerende, ikke CMS"** — tre handlinger plus oversigt, ingen
fakta-redigering herfra:

1. **Pins/skjul-oversigt:** alle `feed_pin`-rækker (nøgle, handling, oprettet-tidspunkt)
   med fjern-handling (`fjernFeedPin`). Dinglende nøgler (uden modsvarende kort i den
   aktuelle model) markeres visuelt, så redaktøren kan rydde op — motoren er ligeglad
   (§4.4), men oversigten skal være ærlig.
2. **Publicerede stories:** liste med afpublicér-handling — afpublicér =
   `setStoryStatus(…, 'klar')` (tilbage til "færdig men ikke i feed"; arkivering er den
   stærkere handling og findes i editoren, §7.2).
3. **Pin/skjul et kort:** browse person- og story-lister (genbrug af de eksisterende
   liste-/søgemønstre i Redaktion.tsx) og vælg handling — der bygges `kort_noegle` af de
   kendte formater (`'portrait:'+personId`, `'story:'+storyId`, `'arkiv:'+haendelseId`)
   og sendes `setFeedPin`.

**Mobil får IKKE denne side.** Mobilens kurering er kun inline på
person-redaktionssiden: pin/skjul-handling ud for personens portræt-kort-identitet
(`'portrait:'+personId`) og ud for personens stories — samme `Change`-arter, samme
dry-run-flow.

### 7.4 Web-startpersoner fra pins (`web/src/data/home.ts`)

Heroen "Redaktionen foreslår · begynd her" skifter kilde: en ny ren, testbar helper
udleder startpersonerne af portræt-pins og falder tilbage til den eksisterende
heuristik:

```ts
export function forsideStartpersoner(
  model: Model,
  pins: FeedPinInput[],
  n: number,
): ModelPerson[];
```

Reglen: tag pins med `handling === 'pin'` og `kortNoegle` på formen `'portrait:<id>'`
(præfiks-parse — andre nøgleformer ignoreres her), slå personerne op i `model.byId`
(ukendt/privat-bortfiltreret id springes over), bevar pin-ordenen; er der færre end `n`,
fyldes op med `curatedFounders(model, n)` minus allerede valgte. **`curatedFounders`
beholdes uændret som fallback** — med nul pins er forsiden identisk med i dag
(home.ts-kommentarens "endnu ingen redaktionel highlights-tabel" opdateres, for nu
findes den). `HomeView` får pins fra samme `feedPins`-load som feed-strømmen — intet
ekstra netværkskald. Test: vitest på helperen (pins først i orden, dinglende
portrait-pin ignoreres, fallback-udfyldning uden dubletter, tom pin-liste ⇒ identisk med
`curatedFounders`).

---

## 8. Skive 6 — CI + afstemning

- **Ingen nye CI-jobs:** fase 3 tilføjer ingen ny pipeline eller nyt sprog — alle nye
  tests lander i suiter der allerede kører i `.github/workflows/ci.yml`
  (`packages/feed` vitest; web vitest + build; mobil tsc + jest). R-suiten (`r ·
  testthat`) kører uændret — fase 3 har ingen R-flade (ingen loader-/pipeline-ændringer).
  Implementer verificerer at alle suiter er grønne som gate pr. skive.
- `db-verify.sql` køres manuelt mod kopi-basen (med fase 2 anvendt først, §2) — CI har
  ingen base-service, samme vilkår som fase 2.
- `docs/changelog.md`-post + statuslinje ved implementeringens afslutning;
  `docs/README.md`-indeksering af denne spec; feed-konceptets §10 opdateres med
  fase 3-status og spec-link (som fase 1/2-linkene).
- `docs/database-current-state.md` opdateres først når migrationen reelt er kørt mod
  prod — prod-kørslen er sin egen gated handling (fase 4-runbook-disciplinen), og den
  omfatter fase 2 + fase 3 i rækkefølge samt gen-anvendelse af `db-rls.sql` (så
  story-/pin-politikkerne og `red\_%`-grant-loopet lander) og `get_advisors(security)`.

---

## 9. Globale bindinger

1. **Additivitet:** migrationen er rent additiv; evidenslaget
   (fact/assertion/conclusion/citation/narrative) OG hændelseslaget (`haendelse` +
   pipeline) er urørte. Ingen eksisterende tabel, politik eller RPC ændres.
2. **Ren motor:** `@daa/feed` forbliver uden netværk, `Date.now` og `Math.random` — al
   ny dynamik injiceres (`storieBy`, `pins`, `todayISO`). Regressions-invarianten (§4.5)
   håndhæves som eksplicit test: uden stories og pins er ordningen dybt identisk med
   fase 2.
3. **GDPR (invariant #8, koncept §9):** feed'en viser kun afdøde —
   `entitet_offentlig`-gaten i story-RLS'en fail-closer på levende/private/stagede
   subjekter; `story.privat` respekteres i RLS OG som klient-filter
   (defense-in-depth). `feed_pin` bærer ingen PII og er derfor offentligt læsbar (§3.5).
4. **Intet LLM i fase 3:** ingen Edge Functions, ingen genererings-knapper, ingen
   LLM-kald — `oprindelse='redaktoer'` er hårdkodet i `red_opret_story`, og
   `llm_*`-kolonnerne står tomme til fase 4.
5. **Prod er gated:** kopi-base hele vejen; prod-migrering (fase 2 + fase 3 sekventeret,
   §2) er en separat, brugergodkendt handling.
6. **Stil-disciplin:** ingen nye farver/fonte (kun tokens); dansk prosa i UI, SQL-
   kommentarer og commits (`feat(feed): …`).

---

## 10. Risici & modforanstaltninger

- **Pin/lås-interaktionens kompleksitet** (blok + dagensperson-lås + slægt-lås + R3-
  forcing) → eksplicitte offset-regler (§4.4: alt forskydes med blokkens længde P;
  pinnet låse-kort ⇒ låsen udgår tavst), ingen ekstra RNG-forbrug, og
  regressions-invarianten som hårdt værn: P=0 ⇒ identisk med fase 2. Pin-testene
  dækker kollisionstilfældene (§4.5).
- **To skjul-stier kan forvirre** (`feed_status='skjult'` vs. `feed_pin`-skjul) →
  dokumenteret ortogonalitet (§4.4: indholds-dom pr. hændelse vs. kurering pr. kort-id)
  i både spec og `order.ts`-kommentar; redaktions-UI'et holder dem adskilt (statuspiller
  på tidslinjen vs. pin/skjul på styringssiden).
- **Story mister sit anker ved hændelses-regenerering** → `ON DELETE SET NULL` (§3.1):
  historien overlever, kortet degraderer ærligt (kategori `null`, dedup-eksklusionen
  bortfalder så hændelsens arkiv-kort kan dukke op igen ved siden af historien — synligt
  for redaktøren, rettes ved at gen-forankre via `redigerStory`).
- **Fase 2's prod-migration udestår** → sekventeringskravet i §2: kopi-basen skal have
  fase 2 anvendt før fase 3's verify kan køre; prod får begge i rækkefølge. Ingen
  fase 3-artefakt må antage at prod allerede har `haendelse`.
- **Mistet indhold ved sletning** → normal vej er blød (`'arkiveret'`); hård
  `red_slet_story` er fortrydbar via fuld versionering (§3.6/§3.7) — undtagen
  kildelisten, hvis erstat-semantik er dokumenteret og gen-kørbar
  (`red_set_story_kilder`).
- **Dinglende pins akkumulerer** → motoren ignorerer dem tavst (aldrig crash, §4.4);
  styringssiden markerer dem visuelt til manuel oprydning (§7.3).
- **Payload-volumen** → stories er få (redaktionelt skrevne — tocifret/lavt trecifret
  antal i overskuelig fremtid) og pins færre endnu; queries er felt-slanke og chunkede.
  Skulle mængden engang vokse, gælder samme målepunkt som hændelses-loadet
  (server-filtreret hentning bag samme loader-kontrakt — motoren ændres ikke).
- **Tomme tabeller før første story/pin** → alle klientlag degraderer til præcis
  fase 2-adfærd (regressions-testet, §4.5) — skiverne kan landes i vilkårlig rækkefølge
  efter skive 1, og feed'en er aldrig afhængig af redaktionel kapacitet (koncept ✓d
  består: arkiv-kortene bærer feed'en indtil historierne kommer).

---

## 11. Succeskriterier

- Migrationen er idempotent (to kørsler af `db-migrations.sql` = én); db-verify-asserts
  grønne mod kopi-base med fase 2 anvendt: kladder/private/levende-subjekt-stories
  usynlige for anon og authenticated, publiceret+afdød synlig, `feed_pin` læsbar for
  anon, CHECK/UNIQUE/RPC-gates afviser korrekt, og fortryd genskaber både status-skift
  og hel story (fuld versionering bevist). `get_advisors(security)` uden nye fund.
- Redaktøren kan — med dry-run-preview og versionshistorik — skrive en historie ud fra
  en hændelse (forudfyldt titel/tekst/dato/kilder), publicere den, og se den som
  `historie`-kort med kildefod i feed'en; afpublicere fra styringssiden; pinne et kort
  til toppen og skjule et andet — og alle tre effekter slår igennem i klient-feed'en
  efter genindlæsning.
- Motor-beviserne (vitest): pin-blok først, skjulte kort-id'er aldrig i output,
  historie-kort dominerer statistisk (BASE 1,2 + nyligt-publiceret-boost),
  historie/arkiv/citat-dedup pr. hændelse, dinglende pins ufarlige — og **uden stories
  og pins er ordningen dybt identisk med fase 2** over de eksisterende fixtures.
- Web-forsidens startpersoner følger portræt-pins med `curatedFounders` som verificeret
  fallback (tom pin-liste ⇒ uændret forside).
- `tsc` + alle suiter grønne (feed/web/mobil/r) uden nye CI-jobs; ingen ændringer i
  evidens- eller hændelseslaget (kun additivt skema + nye læsninger/skrivninger i det
  nye lag).

---

## 12. Åbne koncept-beslutninger (status i denne fase)

- **○c — skal `historie`-kort vise AI-oprindelse?** Moot i fase 3: alt er
  `oprindelse='redaktoer'`, så der er intet at vise. Skemaet bærer feltet
  (+ `llm_model`/`llm_promptversion`/`llm_naar`) så fase 4 kan besvare spørgsmålet som
  ren visnings-/politik-beslutning uden migration.
- **○b — hændelses-gruppering på tværs af udgaver** — fortsat fase 4; `story` forankres
  i fase 3 i én konkret hændelse (eller frit).
- **`feed_pin.gaelder_fra/til`** (tidsbegrænsede pins) — udgået her (YAGNI, §3.3); kan
  tilføjes additivt hvis et reelt behov opstår (sæsonkurering el.lign.).
