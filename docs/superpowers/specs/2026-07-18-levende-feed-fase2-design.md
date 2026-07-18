# Levende feed — fase 2: hændelses-skelettet & arkivkort (design-spec)

**Dato:** 2026-07-18
**Styringsgrundlag:** `docs/design/2026-07-18-levende-feed-koncept.md` §3 (hændelses-skelet)
+ §10 (fase 2).
**Implementeringsplan:** følger separat (task-for-task, TDD — som fase 1).
**Mål:** feed'en bliver hændelses-drevet: et offline LLM-pass projicerer de bevarede
narrativer til en ny `haendelse`-tabel (formidlingslag, additivt), klienterne indlæser
hændelserne, feed'en får `arkiv`-kort og rigere `paadennedag`-kort, citat-kortet skifter
kilde fra sætnings-heuristik til reelle klausuler, og redaktionen får en læsbar
hændelses-tidslinje med én skrivehandling: markér `feed_status`. Alt uden krav om
redaktionel skrivning — og uden at røre evidensmodellen.

**Beslutninger arvet fra konceptet:** ✓a (formidlingslag, ikke mere evidens — `haendelse`
er en regenererbar projektion af prosaen), ✓d (arkivkort må vises uden redaktionel
godkendelse; `feed_status='skjult'` er opt-out), ✓f (LLM kun offline/redaktionelt, kun
afdøde, aldrig live). **Beslutninger truffet her:** (1) `feed_status`-vokabularet er
`kandidat | interessant | skjult` — konceptskitsens fjerde værdi `ingen` udgår som
redundant med `kandidat` (koncept §7.2 siger selv "umarkerede er kandidat"); (2)
konceptskitsens `gruppe_id` (hændelses-gruppering på tværs af udgaver, åben ○b) udelades
af skemaet — den er fase 4-stof og kan tilføjes additivt.

---

## 1. Baggrund & afgrænsning

I dag (empirisk, efter fase 1): `@daa/feed` (`packages/feed/src/`) er en ren motor med 11
korttyper, pool → score → seeded trækning → strøm-API; mobil og web doserer via
`createFeedStream`. Citat-kortet klipper stadig i bio-prosaen via `firstQuotableSentence`
(`pool.ts:15`, første sætning 40–180 tegn) — den kendte kluntethed blev bevidst accepteret
"endnu en fase" (fase 1-spec §1). De daterede gerninger ("vidne 1247", "lenshyldning
1580") ligger kun i den monolitiske `narrative`-prosa; `fact` har intet beskrivelsesfelt,
og evidens-udtrækket skal ikke udvides (invariant, koncept §3.1). Redaktionen har
fakta-kort (`FaktaKort.tsx` / `renderFactCard`) men ingen kronologisk tidslinje.

**I scope:** `haendelse`-tabellen (additiv migration + RLS + én ny RPC + versionering af
`feed_status`); en ny offline pipeline-skill (`.claude/skills/daa-haendelser/`) efter
daa-extract-mønstret (deterministisk eksport → LLM pr. narrativ → blokerende validering →
R-load med markering-bevarende merge); klient-load i begge apps efter livsdato-mønstret;
`arkiv`-kortet + hændelses-udvidet `paadennedag` + klausul-drevet citat-kort i
`@daa/feed`; redaktionens hændelses-tidslinje (læse + markér `feed_status`, dry-run/LIVE
som alle andre writes).

**Ikke i scope (senere faser, jf. koncept §10):** `story`/`story_kilde`/`feed_pin`-
tabellerne og `historie`-kortet (fase 3); `FeedOverride` forbliver no-op; story-editor og
"Ny historie"-knap (fase 3); LLM-assist-knappen "Foreslå historie", Edge Functions og
batch-kladder (fase 4); hændelses-gruppering på tværs af udgaver (○b, fase 4); push.
Passet kører i v1 kun over **person**-narrativer (`narrative.subjekt_type='person'`) —
tabellen er polymorf klar til family/lineage/estate, men de venter. Levende/private/
staged personers narrativer sendes **aldrig** til LLM'en (§4.1).

**Invariant-afstemning (invariant #4 + #1):** `haendelse` bærer ingen assertion/
conclusion og konkurrerer aldrig med evidenslaget — den er en **envejs-projektion af
`narrative`-prosaen**, nøjagtig som `person.visning_*` er en envejs-projektion af
konklusionerne: regenererbar, kasserbar, aldrig redigeret som sandhedskilde. Vil nogen
bestride en hændelse, retter man prosaen (eller strukturerer et fact) — og hændelsen
følger med ved næste regenerering. Den ene ikke-projicerede kolonne er `feed_status`
(redaktørens dom); den overlever regenerering via en stabil nøgle (§9) og versioneres som
alle andre redaktions-writes — samme opdeling som `version_pk_registry` allerede bruger
for `person` (varige kolonner logges, `visning_*` er skip_cols). "Hver trykt DAA-udgave
er en selvstændig kilde" er gratis opfyldt: hændelser hænger på `narrative_id`, og
narrativer findes pr. (subjekt, source) — to udgaver af samme biografi giver to
uafhængige hændelses-sæt.

---

## 2. Skæring (6 skiver)

| # | Skive | Nye/ændrede filer | Grænse/test |
|---|---|---|---|
| 1 | DB: `haendelse` + vocab + RLS + RPC + versionering | `schema.sql`, `db-migrations.sql`, `db-rls.sql`, `db-verify.sql` | idempotent migration; db-verify-asserts (skjult/levende skjules, CHECK afviser) |
| 2 | Offline pipeline (skill) | `.claude/skills/daa-haendelser/{SKILL.md,references/*,scripts/*}` | unittest på validering/nøgle; R-testthat på merge-helpers; `--dry-run` |
| 3 | Klient-load | `packages/feed/src/haendelser.ts`, `mobile/src/data/haendelser.ts` + `load.ts` + `useStore.ts`, `web/src/data/haendelser.ts` | vitest på ren join; tolerant load (fejl ⇒ `{}`) |
| 4 | Feed-motor: arkiv/paadennedag/citat | `packages/feed/src/{types,pool,temporal,score,order}.ts` | vitest: disjunkthed, fallback, determinisme |
| 5 | Redaktionens hændelses-tidslinje | `mobile/src/data/redaktion{Read,Write}.ts`, `mobile/src/components/redaktion/HaendelseTidslinje.tsx`, `web/src/data/redaktion{Read,Write}.ts`, `web/src/Redaktion.tsx` | jest/vitest på mappers + `buildRpcCall`; dry-run-preview |
| 6 | CI + afstemning | `.github/workflows/ci.yml`, `docs/changelog.md`, `docs/README.md` | nyt pipeline-testjob grønt; fuld suite grøn |

1 er forudsætning for 2, 3 og 5; 3 er forudsætning for 4; 2 kan bygges parallelt med 3–5
(klientlagene degraderer tolerant mod en tom tabel, så de kan landes før første
pipeline-kørsel); 6 sidst. Hver skive holder `tsc` + eksisterende suiter grønne.

---

## 3. Skive 1 — DB: `haendelse`-tabellen

### 3.1 Skema (`schema.sql` + idempotent spejl i `db-migrations.sql`)

```sql
-- FORMIDLINGSLAG (feed-koncept §3.1): dateret hændelse FUNDET I et narrativ. En
-- regenererbar envejs-projektion af prosaen (som person.visning_* er det af
-- konklusionerne) — bærer INGEN assertion/conclusion og konkurrerer aldrig med
-- evidenslaget; bestrides indholdet, rettes prosaen/faktaene og passet gen-køres.
-- Eneste varige kolonne er feed_status (redaktørens dom) — overlever regenerering
-- via (narrative_id, noegle), se fase2-spec §9.
CREATE TABLE IF NOT EXISTS haendelse (
  id             BIGINT PRIMARY KEY,
  subjekt_type   TEXT NOT NULL,          -- polymorf (v1: kun 'person'); = narrativets subjekt
  subjekt_id     BIGINT NOT NULL,
  narrative_id   BIGINT NOT NULL REFERENCES narrative(id) ON DELETE CASCADE,
  noegle         TEXT NOT NULL,          -- stabil regenererings-nøgle (normaliseret klausul, §9) — afledt deterministisk, ALDRIG af LLM
  span_start     INTEGER,                -- tegn-offset i narrative.tekst (klausulens position)
  span_laengde   INTEGER,
  klausul        TEXT NOT NULL,          -- ordret prosa-uddrag ("1580 deltog han i lenshyldningen …")
  kategori       TEXT,                   -- vocab 'haendelse_kategori' (rytme/filtrering, ikke evidens)
  date_min DATE, date_max DATE,          -- fuzzy dato — SAMME mønster som assertion (schema.sql-konvention)
  date_qualifier TEXT,                   -- 'exact','before','after','about','between',... (assertion-vokabularet)
  date_raw       TEXT,                   -- ordret datotekst fra klausulen
  feed_status    TEXT NOT NULL DEFAULT 'kandidat'
                   CHECK (feed_status IN ('kandidat','interessant','skjult')),  -- vocab 'haendelse_feed_status'
  fact_id        BIGINT REFERENCES fact(id),      -- dedup: klausulen dækker et allerede struktureret rygradsfaktum
  relation_id    BIGINT REFERENCES relation(id),  -- dedup: … eller en struktureret relation (gods/embede)
  pass_version   TEXT,                   -- proveniens: prompt-version fra haendelse-prompt.md-headeren
  UNIQUE (narrative_id, noegle)
);
CREATE INDEX IF NOT EXISTS ix_haendelse_subjekt   ON haendelse(subjekt_type, subjekt_id);
CREATE INDEX IF NOT EXISTS ix_haendelse_narrative ON haendelse(narrative_id);
```

Konventions-afstemning: surrogat-BIGINT-PK uden IDENTITY (basens `max(id)+1`/`nid()`-
mønster); fuzzy dato genbruger assertion-felterne 1:1; `feed_status` får DB-CHECK (lille
lukket sæt, som `person.koen`), mens `kategori` valideres i pipelinen mod `vocab` uden
CHECK (åbent-ish sæt, som `faktatype`). `ON DELETE CASCADE` på `narrative_id`: en
projektion dør med sit substrat (samme begrundelse som `media_variant`→`media`).

### 3.2 Vokabular (invariant #9, idempotent i `db-migrations.sql`)

```sql
INSERT INTO vocab (scheme, code, label) VALUES
  ('haendelse_feed_status','kandidat',   'Umarkeret — må vises som arkiv-kort'),
  ('haendelse_feed_status','interessant','Redaktørens dom: godt feed-stof (boostes)'),
  ('haendelse_feed_status','skjult',     'Aldrig i feed'),
  ('haendelse_kategori','embede','Embede/udnævnelse'),
  ('haendelse_kategori','uddannelse','Uddannelse/immatrikulation'),
  ('haendelse_kategori','rejse','Rejse/udlandsophold'),
  ('haendelse_kategori','krig','Krig/militær tjeneste'),
  ('haendelse_kategori','ejendom','Ejendom/køb/salg/arv'),
  ('haendelse_kategori','kirke','Kirke/kloster/gejstligt'),
  ('haendelse_kategori','hof','Hof/ceremoni/hyldning'),
  ('haendelse_kategori','familie','Familiebegivenhed'),
  ('haendelse_kategori','personligt','Personligt/øvrigt dateret'),
  ('haendelse_kategori','andet','Andet')
ON CONFLICT (scheme, code) DO NOTHING;
```

Kategorilisten spejles i skillens `references/vocab.json` (pipelinens valideringskilde)
— én liste, seedet begge steder, som daa-extract-skillens `seed_vocab()` gør det.

### 3.3 RLS (`db-rls.sql` — samme mønstre som narrative/fact)

```sql
grant select on table public.haendelse to anon, authenticated;
-- Supabase default-privileges giver ellers fuld DML (bookmark-fundet, review 22) — skriv kun via RPC:
revoke insert, update, delete, references, trigger, truncate on table public.haendelse from anon, authenticated;
alter table public.haendelse enable row level security;

-- anon: (1) redaktørens skjult-dom håndhæves i basen (fail-closed), (2) polymorf
-- entitets-gate (person: afdød+ikke-privat+ikke-staged via entitet_offentlig, F-02c),
-- (3) arv narrativets synlighed (privat-flag + dets egen entitets-gate) via RLS-cascade —
-- samme cascade-mønster som note→fact ("arver targetets synlighed").
drop policy if exists anon_read on public.haendelse;
create policy anon_read on public.haendelse for select to anon
  using (
    feed_status <> 'skjult'
    and public.entitet_offentlig(subjekt_type, subjekt_id)
    and exists (select 1 from public.narrative n where n.id = narrative_id)
  );
-- authenticated: fail-close til samme regel som anon (F-02-linjen — medlem ser ikke mere end anon).
drop policy if exists auth_read on public.haendelse;
create policy auth_read on public.haendelse for select to authenticated
  using (
    feed_status <> 'skjult'
    and public.entitet_offentlig(subjekt_type, subjekt_id)
    and exists (select 1 from public.narrative n where n.id = narrative_id)
  );
-- redaktion: ser alt, inkl. skjulte (additivt lag — tidslinjen skal kunne af-skjule).
drop policy if exists redaktion_read on public.haendelse;
create policy redaktion_read on public.haendelse for select to authenticated
  using ((select public.current_rolle()) = 'redaktion');
```

GDPR-arven (invariant #8) er dermed dobbelt: subjektets synlighed (levende/privat/staged
→ `entitet_offentlig` fail-closer) OG kilde-narrativets `privat`-flag (cascade gennem
narrativets egen politik). Klienten filtrerer desuden som defense-in-depth (§5.2).
Implementer skal selv verificere at `exists`-cascaden performer på ~10k rækker
(`ix_haendelse_narrative` + narrativ-politikkens subqueries) — mønstret er identisk med
note/assertion-politikkerne, som allerede kører på større tabeller.

### 3.4 RPC: `red_set_haendelse_status` (eneste skrivevej fra klienterne)

```sql
CREATE OR REPLACE FUNCTION red_set_haendelse_status(p_haendelse_id bigint, p_status text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_stype text; v_sid bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF p_status NOT IN ('kandidat','interessant','skjult') THEN
    RAISE EXCEPTION '''%'' er ikke en gyldig feed-status (kandidat|interessant|skjult)', p_status;
  END IF;
  SELECT subjekt_type, subjekt_id INTO v_stype, v_sid FROM haendelse WHERE id = p_haendelse_id;
  IF v_stype IS NULL THEN RAISE EXCEPTION 'Hændelse % findes ikke', p_haendelse_id; END IF;
  PERFORM begin_change_set('red_set_haendelse_status',
    format('Satte feed-status %s på hændelse %s', p_status, p_haendelse_id), v_stype, v_sid);
  UPDATE haendelse SET feed_status = p_status WHERE id = p_haendelse_id;
END $$;
```

Mønster: `red_set_koen`/`red_set_privat` (gate → validér → `begin_change_set` →
UPDATE). Grant: db-rls.sql's generiske `red\_%`-loop fanger den ved gen-kørsel; da
`db-migrations.sql` ikke gen-anvender RLS-laget (fase 4-runbook-lektien), skal
migrationen selv indeholde `GRANT EXECUTE ... TO authenticated` eksplicit.

### 3.5 Versionering af `feed_status` (og kun den)

```sql
INSERT INTO version_pk_registry (tabel, pk_cols, skip_cols) VALUES
  ('haendelse', ARRAY['id'],
   ARRAY['subjekt_type','subjekt_id','narrative_id','noegle','span_start','span_laengde',
         'klausul','kategori','date_min','date_max','date_qualifier','date_raw',
         'fact_id','relation_id','pass_version'])
ON CONFLICT (tabel) DO UPDATE SET pk_cols=excluded.pk_cols, skip_cols=excluded.skip_cols;
DROP TRIGGER IF EXISTS trg_log_haendelse ON haendelse;
CREATE TRIGGER trg_log_haendelse AFTER INSERT OR UPDATE OR DELETE ON haendelse
  FOR EACH ROW EXECUTE FUNCTION log_change();
```

Præcis B8-mønstret fra `person` (varige kolonner logges, projektionskolonner er
skip_cols): en `red_set_haendelse_status`-write giver ét pænt `change_event` med kun
`{id, feed_status}`, fortrydbar via `red_fortryd_change_set`; pipelinens bulk-load kører
uden aktivt change_set og logger dermed **intet** (`log_change` returnerer NULL uden
`app.change_set_id` — den eksisterende bulk-load-sti). Regen-UPDATEs der kun rører
skip-kolonner no-op'es af `v_foer = v_efter`-tjekket. **Implementer skal selv verificere**
restore-adfærden for den første fortrydelse mod en skip_cols-tung tabel
(`_version_upsert_row` med partial row hvor rækken stadig findes = ren UPDATE-sti; en
fortrydelse af en DELETE kan derimod ikke genskabe skip-kolonnerne — acceptabelt, da kun
loaderen sletter, uden change_set, men det skal bekræftes i `db-verify.sql`).

### 3.6 `db-verify.sql`-asserts (kør mod kopi-base)

- `to_regclass('public.haendelse') IS NOT NULL`; CHECK afviser `feed_status='ingen'`.
- Seed temp-hændelse på levende person ⇒ usynlig som anon; på afdød + `skjult` ⇒
  usynlig som anon/authenticated; på afdød + narrativ `privat=true` ⇒ usynlig.
- `red_set_haendelse_status` afvises uden redaktion-rolle; ugyldig status afvises.

---

## 4. Skive 2 — offline pipeline: `.claude/skills/daa-haendelser/`

Ny skill der genbruger daa-extract-**mønstret** (deterministisk input → LLM pr. post →
blokerende validering → R-load), men med tre bevidste forskelle: input er **færdige
narrativer fra databasen** (ikke rå PDF-tekst — trin ①/② pdftotext+segment erstattes af
én eksport-query); output er **`haendelse`-rækker** (ikke person/fakta/familie-rækker);
og loadet er en **markering-bevarende merge** (ikke append af nye entiteter).

```
narrativer (DB) ──①export_narratives.R──> work/haendelser/narrativer.json
  ──②LLM pr. narrativ──> work/haendelser/extracted/<narrative_id>.json
  ──③validate_haendelser.py──> {clean.json, review.json, escalation.json}
  ──③b Opus-eskalering (flaggede narrativer, ét forsøg — daa-extract §④b-mønstret)
  ──④load_haendelser.R──> Supabase (merge pr. narrativ; feed_status urørt)
```

### 4.1 ① `scripts/export_narratives.R` (deterministisk)

Forbinder som loaderne (`~/.Renviron`, session-pooler). **GDPR-filteret ligger i selve
queryen** — scriptet kører som ejer og bypasser RLS, så filtret må aldrig være implicit:

```sql
SELECT n.id AS narrative_id, n.subjekt_id, n.source_id, n.side, n.tekst,
       s.udgave, p.visning_navn
FROM narrative n
JOIN person p ON p.id = n.subjekt_id
LEFT JOIN source s ON s.id = n.source_id
WHERE n.subjekt_type = 'person'
  AND coalesce(n.privat, false) = false
  AND p.levende = false                     -- fail-closed: NULL-levende udelukkes (som person_offentlig)
  AND coalesce(p.privat, false) = false
  AND coalesce(p.staged, false) = false;
```

Kun afdøde, offentlige personers prosa når LLM'en (koncept §8-princippet, håndhævet
allerede her — ikke først ved load). Output: én JSON-record pr. narrativ.

### 4.2 ② LLM-udtræk pr. narrativ (`references/haendelse-prompt.md`, frossen)

Samme prompt-disciplin som `extract-prompt.md`: filen er den autoritative kontrakt,
redigeres i repoet (aldrig ad hoc), med `prompt-version:`-header der bumpes ved ændringer
— versionen skrives i `haendelse.pass_version` (proveniens pr. række). Sonnet default;
Opus kun som eskalering af flaggede narrativer (③b). Promptens struktur (skitse — selve
ordlyden skrives ved implementering):

1. **Opgave:** find alle DATEREDE hændelser i narrativets prosa; returnér ét JSON-objekt
   pr. narrativ efter `references/haendelse-schema.json`.
2. **Klausul-reglen (BLOKERENDE, spejler kilde_span/R7):** `klausul` SKAL være et ordret
   substring af narrativ-teksten — mindste sammenhængende uddrag der bærer hændelsen
   (typisk ét prædikat + dato). Opfind aldrig; parafrasér aldrig; typografi skal matche.
3. **Dato-reglen (spejler date_raw-reglen):** `date_raw` kopieres verbatim fra klausulen;
   `date_min/max` MÅ udfyldes men overskrives deterministisk i trin ③. `date_qualifier`
   efter assertion-vokabularet ('about' for ca./o., aldrig 'circa').
4. **Kategori:** én kode fra vokabular-listen (medsendes i prompten fra `vocab.json`);
   i tvivl → 'andet'.
5. **Hvad der IKKE er en hændelse:** rene attributter uden dato, rygradens fødsel/død/
   dåb/begravelse-sætninger (de MÅ medtages — dedup sker i load — men skal ikke jages),
   tredjeparts-personers gerninger (kongens kroning er kun en hændelse hvis subjektet
   deltog i klausulen).
6. **Returnér kort status, ikke fuld JSON** (batch-hygiejne som extract-prompt.md).

`references/haendelse-schema.json` (draft-07, `additionalProperties:false` — R5-mønstret):

```json
{ "required": ["narrative_id", "haendelser"],
  "properties": {
    "narrative_id": {"type": "integer"},
    "haendelser": {"type": "array", "items": {
      "required": ["klausul"],
      "properties": {
        "klausul":        {"type": "string"},
        "date_raw":       {"type": ["string","null"]},
        "date_min":       {"type": ["string","null"]},
        "date_max":       {"type": ["string","null"]},
        "date_qualifier": {"type": ["string","null"], "enum": ["exact","before","after","about","between","floruit","until_event","open_end","ongoing",null]},
        "kategori":       {"type": ["string","null"]}
      }}}}}
```

Bemærk hvad LLM'en **ikke** leverer: `span_start/laengde` (beregnes deterministisk i ③
fra den verbatime klausul — en model skal aldrig tælle tegn-offsets), `noegle` (afledes
deterministisk, §9), `fact_id/relation_id` (matches i load, §4.4). Samme arbejdsdeling
som daa-extract, hvor `boern`/`date_min/max`/narrativen alle er deterministiske trin.

### 4.3 ③ `scripts/validate_haendelser.py` (deterministisk, BLOKERENDE)

```bash
python3 scripts/validate_haendelser.py work/haendelser/narrativer.json work/haendelser/extracted/ \
  --clean work/haendelser/clean.json --review work/haendelser/review.json --escalate work/haendelser/escalation.json
```

Regler (nummereret H1… som daa-extracts R1…; ét blokerende brud → hele narrativets
udtræk i `review.json`, loades ikke):

- **H1 (blokerende):** hver `klausul` er ordret substring af narrativ-teksten
  (hallucinations-værnet — pendant til R7).
- **H2 (blokerende):** hvert årstal i `date_raw` forekommer i klausulen (pendant til R1).
- **H3 (blokerende):** ingen ukendte felter (pendant til R5).
- **H4 (deterministisk berigelse):** `date_min/max` udledes af `date_raw` +
  `date_qualifier` og overskriver LLM'ens bud — **implementer skal selv verificere** om
  daa-extracts dato-parser i `validate.py` kan importeres/udtrækkes som delt modul frem
  for at duplikeres (samme kanoniske parser er et mål i sig selv).
- **H5 (deterministisk berigelse):** `span_start/span_laengde` beregnes som klausulens
  første endnu-ubrugte forekomst i narrativ-teksten (forekomst-indekseret, så to ens
  klausuler får hver sit span).
- **H6 (deterministisk berigelse):** `noegle` afledes af klausulen (§9).
- **H7 (advisory):** `kategori` findes i `references/vocab.json`s
  `haendelse_kategori`-liste; ukendt kode → advisory (drift-signal), værdien erstattes
  af 'andet'.
- **H8 (advisory, eskalerings-signal):** narrativ med ≥N år-tokens i prosaen men 0
  udtrukne hændelser → `escalation.json` (pendant til R8's "prosa nævner X, intet
  udtrukket"). Tærskel fastlægges empirisk ved implementering.

③b genbruger eskalerings-driften fra daa-extract §④b (snapshot → Opus-subagent →
deterministisk re-validering + promotion). **Implementer skal selv verificere** om
`escalate_merge.py` kan genbruges parametrisk eller om skillen får sin egen lille
pendant — logikken (promotér kun hvis Opus består uden blokerende brud og ikke er
dårligere på advisory-målet) er den samme.

Tests: `scripts/test_validate_haendelser.py` (unittest, som `test_validate.py`) — H1-H8,
span-forekomst-indeksering, nøgle-determinisme (samme input → samme nøgler, to ens
klausuler → '#2'-suffiks), dato-udledning.

### 4.4 ④ `scripts/load_haendelser.R` (merge, ikke append)

```bash
Rscript .claude/skills/daa-haendelser/scripts/load_haendelser.R work/haendelser/clean.json [--dry-run]
```

Én transaktion (dbBegin/tryCatch/rollback — load_daa.R-mønstret); id'er fra
`MAX(id)`-sekvensen (`seed_seq`/`nid`-mønstret); `--dry-run` printer buffer-tællinger og
ruller tilbage. **Ingen `--reset`:** loaderen berører kun hændelses-rækker for de
narrativer der indgår i kørslens input — en delkørsel efterlader alt andet urørt.

Pr. narrativ i clean.json:

1. **Re-verificér mod DB-teksten:** klausulen skal stadig være substring af den *aktuelle*
   `narrative.tekst` (den kan være redigeret siden eksporten — `red_upsert_narrativ`).
   Span genberegnes mod DB-teksten; fejler substring-tjekket, springes hændelsen over og
   logges i `work/haendelser/load-unresolved.csv` (aldrig tavst — load_daa.R-princippet).
2. **Rygrads-dedup (`fact_id`/`relation_id`):** konservativ match mod personens
   eksisterende evidens: et fact hvis *valgte* assertion (via conclusion
   `status='afklaret'`) har identisk ikke-NULL `(date_min, date_max)` ELLER identisk
   normaliseret `date_raw` → sæt `fact_id`; tilsvarende for relationers
   assertion/`periode_raw` → `relation_id`. Ingen match → NULL (hændelsen er "ny" viden
   i formidlingslaget). Bevidst konservativt: en falsk kobling skjuler et arkiv-kort
   (§6.2-reglen), en manglende kobling koster højst en dublet-flavor — fejl til den
   billige side.
3. **Markering-bevarende merge** på `(narrative_id, noegle)` — se §9 for den fulde
   algoritme og hvordan `feed_status` overlever.

Rene merge-/nøgle-helpers lægges i `scripts/load_haendelser_helpers.R` og testes DB-frit
i `tests/testthat/test-haendelse-merge.R` (kører i det eksisterende `r · testthat`-CI-job
— duckdb/DB-service-frit som resten af R-suiten).

`work/` er fortsat git-ignoreret (kan indeholde persondata i mellemformer — selvom
eksporten kun tager afdøde, gælder disciplinen).

---

## 5. Skive 3 — klient-load

### 5.1 Ren join i `@daa/feed` (`packages/feed/src/haendelser.ts`)

Spejler `buildLivsdatoBy`-kontrakten (rå PostgREST-rækker ind, kanoniseret opslag ud;
ingen netværk i pakken):

```ts
export interface HaendelseRow {
  id: string | number; subjekt_id: string | number; narrative_id: string | number;
  klausul: string; kategori: string | null;
  date_min: string | null; date_max: string | null;
  date_qualifier: string | null; date_raw: string | null;
  feed_status: string; fact_id: string | number | null; relation_id: string | number | null;
}
export interface HaendelseNarrativRow { id: string | number; source_id: string | number | null; side: string | null; }
export interface HaendelseSourceRow   { id: string | number; udgave: string | null; }

export interface HaendelseItem {
  id: string;                       // haendelse.id som streng (kort-id-byggesten)
  klausul: string;
  kategori: string | null;
  dato: FuzzyDato;                  // {min, max, qualifier} — genbruger fase 1-typen
  dateRaw: string | null;
  interessant: boolean;             // feed_status === 'interessant' ('skjult' når aldrig klienten — RLS)
  rygrad: boolean;                  // fact_id/relation_id sat ⇒ dækket af strukturen (kort-regler §6)
  kilde: string | null;             // fx 'DAA 2018-20, s. 209-211' — kildefoden på arkiv-kortet
}
export type HaendelserBy = Record<string, HaendelseItem[]>;  // kanonisk person-id → kronologisk sorteret

export function buildHaendelserBy(
  rows: HaendelseRow[],
  narrativer: HaendelseNarrativRow[],
  sources: HaendelseSourceRow[],
  canonicalIdById: Record<string, string> = {},
): HaendelserBy;
```

Deterministisk sortering pr. person: `date_min` (NULL sidst) og dernæst `id` —
stabilitet er en motor-forudsætning. `feed_status==='skjult'` filtreres defensivt selv
om RLS allerede fjerner dem (klient-filter som defense-in-depth, koncept §9.2).

### 5.2 App-loadere (spejlpar, livsdato-mønstret 1:1)

`mobile/src/data/haendelser.ts` og `web/src/data/haendelser.ts` — samme form som
`livsdato.ts`-parret: `getAll` + `IN_CHUNK=200`-chunking, tolerant (`try/catch` →
tomme rækker + `console.warn('[haendelser] utilgængelig — arkiv-/hændelseskort udelades')`
— feed'en brydes aldrig; mod en base uden migrationen degraderer alt til fase 1-adfærd):

```ts
export async function fetchHaendelseRows(sb): Promise<HaendelseRowsResult>  // 3 queries: haendelse → narrative(id,source_id,side) → source(id,udgave)
export async function loadHaendelserBy(sb, canonicalIdById): Promise<HaendelserBy>
```

Query 1: `sb.from('haendelse').select('id,subjekt_id,narrative_id,klausul,kategori,date_min,date_max,date_qualifier,date_raw,feed_status,fact_id,relation_id').eq('subjekt_type','person').order('id')`.
Query 2/3: narrative-/source-rækker via chunked `.in('id', …)` på de refererede id'er
(narrativ-teksten hentes IKKE — kun source-koblingen til kildefoden). RLS gør resten.

**Mobil-integration** (`load.ts` + `useStore.ts`, livsdato-skabelonen): parallel promise
ved siden af `livsdatoRowsP` (`const haendelserRowsP = fetchHaendelseRows(sb);` før
hoved-batchen; join efter collapse med `collapsed.canonicalIdById`); nyt
`LoadResult.haendelserBy: HaendelserBy`; store-felt `haendelserBy` (kommentar-stil som
`livsdatoBy`), sat i `load()`, `{}` i SEED-fallback (offline-seedet bærer ingen
hændelser — kortene udelades).

**Web-integration** (feed-mount-skabelonen fra `feedAux.ts`): `loadHaendelserBy(...)`
kaldes ved feed-mount sammen med `fetchFeedBios`; ved ankomst genopbygges strømmen med
samme seed og genoptages via `resumeStream` (append-kontrakten fra fase 1 §7.3/§7.4 —
allerede viste kort røres ikke). Implementer skal selv verificere hvor
mount-orkestreringen bor i dag (`web/src/Folgesvend.tsx` iflg. fase 1-implementeringen)
og hænge hentningen på samme sted som bio-hentningen.

### 5.3 Test

Vitest (`packages/feed`): join + kanonisering + sortering + skjult-filter + kilde-
sammensætning (udgave + side; source mangler → `kilde:null`). App-lag: mockede queries
(fejl → `{}`), chunking (>200 id'er → flere kald) — spejl af livsdato-testene.

---

## 6. Skive 4 — feed-motoren: arkiv, på-denne-dag, klausul-citater

### 6.1 Typer (`types.ts`)

```ts
| { kind: 'arkiv'; id: string; personId: string; name: string; klausul: string;
    aarLabel: string | null;          // fx '1580' eller date_raw-uddrag — aldrig fabrikeret præcision
    kategori: string | null; kilde: string | null;  // 'efter DAA 1939, s. 112'-foden
    interessant?: boolean; kicker: string }         // kicker: 'Årbogen skriver'
```

`paadennedag`-varianten udvides: `hvad: 'født' | 'død' | 'hændelse'` + valgfrit
`klausul?: string` (sat når kilden er en hændelse). `FeedInputs` udvides med
`haendelserBy?: HaendelserBy` (udeladt ⇒ fase 1-adfærd — bagudkompatibelt som
`livsdatoBy`). `bookmarkPersonId` virker uændret (`arkiv` har `personId` ⇒ bogmærkbar,
eksisterende kontrakt).

### 6.2 Kort-regler (pool.ts + temporal.ts)

**`arkiv`-kortet** (`buildArkivKort(model, haendelserBy, usedCitatHaendelseIds)`):
kandidat pr. hændelse hvor (a) `rygrad === false` (fact-/relations-dækkede klausuler er
strukturens ejendom — rygradsdatoer har allerede jubilæums-/paadennedag-kort), og (b)
hændelsen ikke er valgt som personens citat (dublet-værn, se nedenfor). `id:
'arkiv:'+item.id`; `aarLabel` fra `dateRaw` (foretrukket, verbatim) ellers årstal af
`date_min`, ellers `null`; person-navn/years fra `model.byId`. Stabil `byIdStr`-sortering
som alle builders.

**Citat-kortet skifter kilde:** `buildPortraitAndCitat(model, excludeId, haendelserBy = {})`.
Partitionen (hash-mod-4, disjunkthed) er urørt; men for en citat-slot-person vælges
citatet nu blandt personens klausuler: kandidater = hændelser med `klausul.length`
40–180 (længde-gaten genbruges som kvalitetsgate — klausuler ER citerbare enheder, men
korte/monstrøse fravælges stadig) og `rygrad === false`; valg =
`stableHash(p.id) % kandidater.length` (deterministisk, dagsuafhængigt).
**Fallback:** ingen brugbar klausul → `firstQuotableSentence(p.bio)` som i dag (koncept
§5: heuristikken beholdes kun som fallback); heller intet dér → slotten falder ud
(uændret). Returtypen udvides til
`{ portraits, citater, usedCitatHaendelseIds: Set<string> }` så ordningen kan ekskludere
valgte klausuler fra arkiv-poolen.

**`paadennedag` udvides** (`buildPaaDenneDag(model, livsdatoBy, todayISO, haendelserBy = {})`):
hændelser med `dato.qualifier==='exact'` + `dato.min` og `rygrad===false` giver
dag-/månedstræf efter præcis samme MM-DD-regler som livsdatoerne;
`id: 'paadennedag:h:'+item.id`, `hvad:'hændelse'`, `klausul` sat. Dag/måneds-fallbacken
afgøres over den SAMLEDE mængde (livsdato- + hændelses-træf) — ét dag-træf fra en
hændelse er nok til at måneds-fallbacken ikke aktiveres. Aldrig fabrikeret præcision:
kun `exact` giver dag-kort (fase 1-reglen, uændret).

### 6.3 Scoring (`score.ts`) og ordning (`order.ts`)

- `BASE.arkiv = 0.5` (krydderi-tier med forbundet — over citat/vaaben, under gods).
- **Redaktionelt signal:** `interessant === true` ⇒ ×2 (gælder `arkiv`; det er fasens
  eneste redaktionelle scoring-krog — pin/hide kommer først i fase 3). Faktoren
  dokumenteres i `score.ts` ved siden af timeliness/personal/seen.
- `paadennedag` med `hvad:'hændelse'` scorer som de øvrige paadennedag-kort (timeliness
  ×4 ved dag-præcision — uændret logik).
- `order.ts`: `buildArkivKort` + det udvidede citat-/paadennedag-kald ledes ind i
  `candidateCards`; `usedCitatHaendelseIds` føres fra citat-builderen til arkiv-builderen.
  Rytme-reglerne (R1–R3) gælder umodificeret — `arkiv` har `personId`, så R2 spreder
  samme persons hændelser automatisk.

### 6.4 Test (vitest)

- Determinisme: samme inputs (inkl. `haendelserBy`) → identisk ordning.
- `haendelserBy` udeladt/tom → ordningen er dybt identisk med fase 1 (regressionsværn).
- Citat: person med klausuler → klausul-citat (deterministisk valg); uden → bio-fallback;
  valgt klausul optræder ALDRIG også som arkiv-kort (dublet-testen).
- Arkiv: `rygrad:true` udelades; `interessant` fordobler score (property-test som fase 1's
  bookmark-test: rykker frem statistisk over fast seed-liste); `skjult` findes aldrig i
  input (loader-filter testes i skive 3).
- Paadennedag: hændelses-dag-træf; blandet fallback (livsdato-månedstræf undertrykkes af
  hændelses-dagtræf); qualifier≠exact ⇒ aldrig dag-kort.
- Tom model / person mangler i `byId` (ikke-kanoniseret id) → ingen crash, kortet udelades.

---

## 7. Skive 5 — redaktionens hændelses-tidslinje

### 7.1 Read-lag (`redaktionRead.ts`, begge apps — spejlpar som i dag)

```ts
export type HaendelsePost = {
  id: number; klausul: string; kategori: string | null;
  dato: { min: string | null; max: string | null; qualifier: string | null; raw: string | null };
  feedStatus: 'kandidat' | 'interessant' | 'skjult';   // redaktion ser også skjulte (redaktion_read)
  narrativeId: number; spanStart: number | null; spanLaengde: number | null;
  sourceTitel?: string; side?: string;
  factId: number | null; relationId: number | null;
};
export function mapHaendelser(rows: …): HaendelsePost[];          // ren, testbar (mapNarrativer-mønstret)
export async function fetchHaendelserForPerson(personId: string): Promise<HaendelsePost[]>;
```

Flad query mod `haendelse` (+ source-titel via narrativ→source, samme nest/join-stil som
`fetchNarrativer`). Fejl kaster (redaktions-reglen fra `fetchKonflikter`: en tavs catch
ville skjule en RLS-fejl som "ingen hændelser").

**Tidslinje-fletning (ren helper, delt idé — én pr. app som `joinEvidence`):**

```ts
export function buildTidslinje(haendelser: HaendelsePost[], evidens: PersonEvidence): TidslinjePost[];
```

Fletter hændelser med rygradsfakta der bærer dato (fra det allerede-hentede
`PersonEvidence` — ingen ekstra queries): én kronologisk liste, hvor rygradsposter
markeres (`art:'rygrad'`) og hændelser med `factId` kobles til deres fakta-post frem for
at dubleres (koncept §7.1: "rygradsfakta flettes ind via fact_id-koblingen så tidslinjen
er komplet"). Sortering: `date_min`, NULL-datoer sidst, stabil id-tiebreak.

### 7.2 Write-lag (`redaktionWrite.ts`, begge apps)

`Change`-unionen udvides:

```ts
| { art: 'haendelseStatus'; subjektType: string; subjektId: string;
    haendelseId: number; status: 'kandidat' | 'interessant' | 'skjult' }
```

`buildRpcCall` mapper til `{ fn: 'red_set_haendelse_status', args: { p_haendelse_id, p_status } }`.
Dermed er **dry-run/LIVE gratis**: `submitChange(change, { dryRun })` returnerer det
planlagte kald til preview-sheeten uden at røre basen, præcis som alle andre writes; webs
`planCall`-rolle-routing degraderer ikke-redaktører til `red_suggest`-staging uændret.
Test: nyt `buildRpcCall`-case i begge apps' eksisterende suiter.

### 7.3 UI — web (`Redaktion.tsx`)

Ny sektion i `renderPersonEditor` mellem Kerne-fakta og familie-relationer:
`sectionHeader('Hændelser · tidslinje fra prosaen')` + én række pr. `TidslinjePost`:
dato-label (verbatim `dato.raw` foretrukket) · klausulen som citat · kategori-badge ·
kildefod (`sourceTitel, side` — `kildeAf`-mønstret) · status-vælger. Status-vælgeren
genbruger **pille-mønstret** fra `KonfidensVaelger`/webs `KONF`-piller: tre piller
(kandidat / interessant / skjult), aktiv pille markeret, klik → `run({art:'haendelseStatus', …},
'Feed-status')` (som re-loader personen efter LIVE — `run`-wrapperen uændret).
Rygrads-poster viser ingen status-vælger (de styres af evidenslaget, ikke feed'et).

**Klausul-i-kontekst:** klik på klausulen åbner narrativ-sektionen på den rette
udgave-fane og markerer spanet. Der findes ingen eksisterende span-highlight-mekanisme
(hverken `NarrativRenderer` eller editoren kan det i dag — verificeret), så MVP'en er
bevidst minimal: sæt narrativ-editorens selektion via det eksisterende
`narrativTextareaRef`-mønster (`focus()` + `setSelectionRange(spanStart, spanStart +
spanLaengde)` — samme mekanik `insertNarrativToken` allerede bruger til cursor-styring).
Span kan være driftet efter en narrativ-redigering: fald tilbage til
`tekst.indexOf(klausul)`, og findes klausulen slet ikke, vises en stille "klausul ikke
længere i narrativet — gen-kør hændelses-passet"-notits. Rig inline-highlight i
`NarrativRenderer` er IKKE i scope.

### 7.4 UI — mobil

Ny komponent `mobile/src/components/redaktion/HaendelseTidslinje.tsx` efter
`FaktaKort`-arkitekturen: komponenten holder egen fold-state og rapporterer via
callback — den kalder aldrig selv write-laget:

```ts
export function HaendelseTidslinje({ poster, onSetStatus }: {
  poster: TidslinjePost[];
  onSetStatus: (haendelseId: number, status: 'kandidat' | 'interessant' | 'skjult') => void;
});
```

Statuspiller i `koenPille`/`koenPilleAktiv`-stilen (samme genbrug som
`KonfidensVaelger`); `onSetStatus` bygger `Change` og sender gennem
`SkrivePreviewSheet`-flowet (dry-run-preview som narrativ-editoren). Placeres på
person-redaktionssiden ved fakta-sektionen — implementer skal selv verificere hvilken
screen-fil der komponerer `FaktaKort`-sektionen i dag og spejle placeringen. Ingen nye
farver/fonte (tokens fra `mobile/src/theme/tokens.ts`).

### 7.5 Test

Jest/vitest: `mapHaendelser` (rå rækker → poster, skjulte medtages for redaktion),
`buildTidslinje` (fletning, factId-kobling frem for dublet, NULL-dato-sortering),
`buildRpcCall`-caset. UI verificeres i simulator/browser mod dry-run (projektets
etablerede mønster); dokumentér hvad der er testet vs. manuelt verificeret.

---

## 8. Skive 6 — CI + afstemning

- **Nyt CI-job** `pipeline · unittest` (mønster: de eksisterende jobs — checkout, ingen
  npm): `python3 -m unittest discover -s .claude/skills/daa-haendelser/scripts -p 'test_*.py'`.
  Kun den nye skills tests gates i denne omgang; daa-extracts `test_*.py` kan hægtes på
  i samme job senere, men skal først verificeres grønne (de har aldrig været CI-gatet —
  gør det ikke blindt i denne fase).
- R-merge-testene (`tests/testthat/test-haendelse-merge.R`) rider på det eksisterende
  `r · testthat`-job — de skal derfor være DB-service-frie (rene helpers, duckdb hvor
  nødvendigt), som resten af suiten.
- `docs/changelog.md`-post + statuslinje ved implementeringens afslutning;
  `docs/README.md`-indeksering af spec + skill; notér i feed-konceptet at fase 2-spec'en
  findes (som fase 1-linket i §10).
- `docs/database-current-state.md` opdateres når migrationen reelt er kørt mod prod
  (deploy-proceduren dér er autoritativ — migrationen designes her, men prod-kørsel er
  sin egen gated handling, jf. fase 4-runbook-disciplinen; husk at db-rls.sql skal
  gen-anvendes for at haendelse-politikkerne og RPC-grantet lander).

---

## 9. Determinisme & regenererbarhed (fasens sværeste designspørgsmål)

Hele værdien af projektions-designet står og falder med at passet kan **gen-køres og
forbedres uden datatab** — konkret: uden at redaktørens `feed_status`-markeringer
forsvinder, og uden at kort-id'er (og dermed set-hukommelse/bogmærke-adfærd) churner
unødigt.

### 9.1 Den stabile nøgle

`noegle` afledes deterministisk i valideringstrinnet (aldrig af LLM'en):

```
normaliser(klausul) = NFC → lowercase → alle whitespace-løb → ét mellemrum → trim → første 160 tegn
noegle = normaliser(klausul)            # + '#2', '#3' … ved identiske klausuler i samme narrativ (forekomst-orden)
```

Rå normaliseret tekst frem for et hash: debugbar i psql, og `UNIQUE (narrative_id,
noegle)` håndhæver integriteten uanset. Egenskaber: uafhængig af span-positionen (en
tilføjet sætning tidligere i narrativet flytter spans men ikke nøgler), uafhængig af
LLM'ens kategorisering/datotolkning (et forbedret pass der retter en fejl-kategori
beholder nøglen), følsom kun over for selve klausul-afgrænsningen.

### 9.2 Merge-algoritmen (i `load_haendelser.R`, pr. narrativ i kørslens input)

1. Hent eksisterende rækker for `narrative_id`; nøgl de nye kandidater.
2. **Match på `(narrative_id, noegle)`** → UPDATE af alle regenererbare kolonner (span,
   kategori, datoer, klausul-original, `fact_id/relation_id`, `pass_version`).
   `feed_status` røres **aldrig** af loaderen — markeringen overlever trivielt.
3. Ny nøgle uden modpart → INSERT (`feed_status` DEFAULT 'kandidat').
4. Eksisterende nøgle uden modpart (passet afgrænser klausulen anderledes nu):
   - `feed_status = 'kandidat'` → DELETE (umarkeret projektion, intet tabes).
   - `feed_status ≠ 'kandidat'` → **sekundær match**: blandt kørslens endnu-umatchede nye
     rækker søges én med samme `kategori` og identiske `(date_min, date_max)`; ved
     præcis ét træf overføres `feed_status` til den nye række og den gamle slettes.
     Ellers slettes rækken, og markeringen logges i
     `work/haendelser/mistede-markeringer.csv` (haendelse-id, nøgle, status, klausul) —
     **aldrig tavst datatab**; loaderen printer antallet, og redaktøren kan gen-markere
     fra tidslinjen. Rækker efterlades bevidst IKKE forældreløse i basen: en projektion
     må ikke indeholde rækker uden substrat-modpart (det ville genindføre præcis den
     to-sandheder-tilstand invariant #4 forbyder).
5. Narrativer der IKKE er med i kørslens input berøres ikke (delkørsler er sikre).

### 9.3 Samspil med resten af systemet

- **Narrativ-redigering:** ændrer redaktøren prosaen, drifter spans (klausul-fallback i
  UI'et, §7.3) indtil passet gen-køres for det narrativ. Anbefalet drift: gen-kør passet
  for redigerede narrativer med jævne mellemrum (kan automatiseres senere — ikke i scope).
- **Versionering:** loaderen kører uden change_set (ingen historik-støj fra tusindvis af
  projektionsrækker); kun `red_set_haendelse_status` skriver historik, og skip_cols-
  registreringen (§3.5) gør hvert event minimalt og fortrydbart.
- **Kort-id-stabilitet:** `arkiv:`/`paadennedag:h:`-id'er bygger på `haendelse.id`, som
  er stabil så længe nøglen matcher (trin 2 er UPDATE, ikke delete+insert) — set-
  hukommelsens decay-vægte overlever dermed en regenerering for uændrede klausuler.
- **Proveniens:** `pass_version` pr. række gør det muligt at se hvilke rækker et
  forbedret pass endnu ikke har nået, og at sammenligne pass-årgange (samme motivation
  som extract-promptens frosne versionering).

---

## 10. Risici & modforanstaltninger

- **LLM-hallucination i klausuler** → H1-substring-tjekket er blokerende; en klausul der
  ikke findes ordret loades aldrig (arkitekturens R7-arv — den farlige fejl er forkert
  udtræk, ikke manglende).
- **Mistede markeringer ved omformulerede klausuler** → sekundær match + CSV-log (§9.2);
  værste fald er en gen-markering fra tidslinjen, aldrig stille tab.
- **Payload-volumen på klienten** (~920 narrativer × anslået 5–15 klausuler = 5–15k
  rækker) → felt-slank query (ingen narrativ-tekst), chunket hentning, tolerant
  degradering. Målepunkt som fase 1's bio-strategi: overstiger payloaden ~2,5 MB,
  overgås til server-filtreret hentning (fx kun `interessant` + et deterministisk
  udsnit af kandidater) bag samme loader-kontrakt — motoren ændres ikke.
- **RLS-ydelse** (narrativ-exists pr. række) → indekser + samme cascade-mønster som
  note/assertion; verificeres mod kopi-base før prod (db-verify + eksplain).
- **Dublet-indhold** (samme klausul som citat OG arkiv; hændelse OG rygrads-kort samme
  dag) → `usedCitatHaendelseIds`-eksklusion + `rygrad`-reglen, begge testet eksplicit.
- **Kategori-drift i LLM-output** → advisory H7 mod vokabular-listen + 'andet'-fallback;
  driften er synlig i valideringsrapporten, ikke i produktet.
- **Regenerering churner kort-id'er** → nøgle-match er UPDATE-baseret (§9.3); kun reelt
  ændrede klausuler får nye id'er.
- **Restore/undo mod skip_cols-tabellen er uprøvet terræn** → db-verify-assert på
  fortryd-af-status-UPDATE (§3.5); DELETE-fortrydelse er eksplicit uunderstøttet og
  dokumenteret (kun loaderen sletter, uden change_set).
- **Tom tabel før første pipeline-kørsel** → alle klientlag degraderer til præcis
  fase 1-adfærd (testet som regression, §6.4) — skiverne kan landes i vilkårlig
  rækkefølge efter skive 1.

## 11. Succeskriterier

- Migrationen er idempotent (to kørsler af `db-migrations.sql` = én); db-verify-asserts
  grønne mod kopi-base: skjulte/levende/private hændelser usynlige for anon og
  authenticated, redaktion ser alt, CHECK og RPC-gates afviser korrekt.
- Pipelinen kørt over prod-kopiens narrativer producerer `haendelse`-rækker hvor **hver
  klausul findes ordret i sit narrativ** (H1 = 0 brud i clean), og en **gen-kørsel oven
  på markerede rækker bevarer alle `feed_status ≠ 'kandidat'`** (eller logger dem i
  mistede-markeringer.csv — aldrig stille tab). `--dry-run` ruller rent tilbage.
- Feed'en viser `arkiv`-kort med verbatim klausul + kildefod; citat-kort kommer fra
  klausuler hvor de findes (heuristik kun som fallback); "på denne dag" kan bære
  hændelser ud over fødsel/død — alt deterministisk pr. seed+dato (vitest-bevist), og
  med tom `haendelserBy` er ordningen bit-identisk med fase 1.
- Redaktøren kan se en komplet kronologisk tidslinje (hændelser + rygrad flettet) på en
  person, hoppe til klausulen i narrativet, og sætte kandidat/interessant/skjult med
  dry-run-preview; markeringen slår igennem i feed'en (interessant-boost / skjult væk)
  og er fortrydbar i historikken.
- `tsc` + alle suiter grønne (core/feed/web/mobil/r + nyt pipeline-job); ingen ændringer
  i evidenstabellerne (fact/assertion/conclusion/citation/narrative urørt — kun additivt
  skema + nye læsninger).
