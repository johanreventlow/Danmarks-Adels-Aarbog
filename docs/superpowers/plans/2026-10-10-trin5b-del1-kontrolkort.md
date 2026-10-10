# Trin 5b del 1 — tillæg: besvarlige kontrolkort (spec §22.9 + §23) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Erstat 5b del 1's ubesvarlige 63-linjers kontrolark med ét ark med blinde ægtefællekort (alle navnefæller + 20 tilfældige) og forældrekort (A/R/F/U), som projektejeren kan besvare med bogen ved hånden.

**Architecture:** Kontrolkørslen (Task 6) bygges om, så den kun vælger identitetssager. Navnefæller tages altid med, `K = 20` tilfældige fordeles med største-rest, og tidsmæssigt umulige kandidater skjules. Personas med umulig rang 1 eller over 2 navnefæller udelukkes og gemmes. Forældrekort gemmes særskilt og afgøres af serveren i en egen transaktion. Rækkefilen bærer hovedperson, bogens ordrette klausul med markeret navnespænd og kandidaternes forældre. Arket renderes, parses og omsættes til SQL af `identity_control_sheet.py`.

**Tech Stack:** PostgreSQL 17 (plpgsql), Python 3 (unittest/pytest), psql. Ingen web-ændringer (webkøen er del 2, §23.5).

**Spec:** `docs/superpowers/specs/2026-10-06-trin5b-relationspersonas-design.md` §22.9 og §23 (commits `719ef4f`, `a772e7c`, `e5e023d`, `1c3b51c`). Tillæg til `docs/superpowers/plans/2026-10-06-trin5b-del1-identitet.md`; samme ledger (`.superpowers/sdd/2026-10-06-trin5b-del1-identitet/progress.md`). Task 10 i hovedplanen erstattes af Task 14 her.

## Global Constraints

- `K = 20` tilfældige ægtefællekort (projektejerens valg 2026-10-10); navnefæller tages alle med; over 40 ægtefællekort ⇒ `IDENTITY_CONTROL_SAMPLE_TOO_LARGE`.
- Kandidatkørslen til kontrollen laves med `--top-k 10`.
- Tokens: `D … : <1-3|X|N|U>` og `R … : <A|R|F|U>`; `P <id>` findes ikke på kontrolarket.
- Ægtefællekort viser aldrig score, tier, signaler, rang, familiemarkør, familie-id eller »allerede gift med«.
- Grænsen rapporteres som `1 − 0,05^(1/K)` alene af de tilfældige kort; ordet »valideret« bruges ikke.
- Forældrelinjer anvendes i en særskilt transaktion efter identitetsdelen; `F` og `U` ændrer ikke påstanden.
- Persondata: navne/klausultekst kun i `~/.private/5b/` (0600/0700); aldrig i chat, repo, commits, ledger. Kør aldrig psql-output med aktør-uuid ufiltreret (memory `set-config-ekko-aktoer`; maskér hex ≥ 8 tegn).
- Kun `ci5b_`-baser og lokale klynger fra `localci.py` må oprettes og droppes frit; andre baser kun karantæne-omdøbning.
- Kør hele CI-jobbet lokalt efter `git add` (memory `koer-hele-ci-jobbet-lokalt`): `localci.py <job> <port>` i scratchpad.
- Commit-trailer: `Claude-Session: https://claude.ai/code/session_018KPNPJmdDmYBKcQQ14VfHb`; ingen Claude-attribution; ingen push.

## Review Focus

1. Hovedperson eller kandidat uden afklarede datoer ⇒ intet fjernes (NULL = ukendt) — test i Task 12 (`candidate_impossible` med NULL).
2. Klausultekst med linjeskift, `#` eller en linje, der begynder med `D `/`R ` ⇒ renderen normaliserer whitespace til ét mellemrum, og `check_render` er stabil — test i Task 13.
3. Forældrekort `A`, hvor familien er ændret efter registreringen ⇒ `familie_aendret`-event, identitetsdelen (transaktion 1) er allerede committet — test i Task 12 (SQL) og Task 13 (SQL-tekstens to transaktioner).
4. Navnefælle, hvor `visning_fuldt_navn` er NULL ⇒ sammenligning på `visning_navn` alene, NULL-sikkert — test i Task 12.
5. Over 2 navnefæller ⇒ personaen udelukkes (`navnefaeller_over_3`) og indgår hverken i stikprøven eller i den maskinelle bekræftelse — test i Task 12.

---

### Task 11: Måling før ombygning (kun tal)

**Files:** ingen kode; tal i ledgeren.

**Interfaces:**
- Consumes: bevisbasen `$(cat <scratchpad>/bevis2-db.txt)` (= `daa5b_bevis_20261010…`), `~/.private/5b/cand-input.json` (fra bevis2.sh).
- Produces: `~/.private/5b/cand-0.95-k10.json` og en kandidatkørsel med `topK=10` i bevisbasen (bruges af Task 14).

- [ ] **Step 1: Kandidatkørsel med top-k 10**

```bash
SP=/private/tmp/claude-501/-Users-johanreventlow-TypeScript-danmarksadelsaarbog/7e06f5a5-f3bd-4134-a920-9b9b99c0eea2/scratchpad
DB=$(cat $SP/bevis2-db.txt); P=$HOME/.private/5b; umask 077
A=$(psql -X -At -d $DB -c "select id from profiles where rolle='redaktion' order by id limit 1")
env -u NODE_OPTIONS npm run cli -w @daa/identity-candidates -- generate --input $P/cand-input.json \
  --source-id 1 --family-name-min 0.95 --top-k 10 --out $P/cand-0.95-k10.json 2>&1 | grep CANDIDATES_OK
psql -X -At -q -d $DB -v actor="$A" -v cand_file=$P/cand-0.95-k10.json -f packages/identity-candidates/sql/write-candidates.sql \
  2>$SP/k10.err | grep -v -- "$A" | tail -1 > $SP/bevis2-run-k10.txt
psql -X -At -d $DB -c "select count(*), max(run_seq) from private.source_persona_identity_candidate_run where source_id=1"
```
Expected: `CANDIDATES_OK … egnede=203` (egnethed og rang 1 er uafhængige af top-k), og 2 kørsler. Ny `config_sha256` ⇒ ny kørsel. Hvis `IDENTITY_CANDIDATE_INPUT_DRIFT` eller lignende: basen er ændret siden `cand-input.json` blev eksporteret. Kør så eksporten igen (bevis2.sh's export-linje) før generate, og ledger en `Ruling:`.

- [ ] **Step 2: Mål navnefæller, umulige rang 1 og skelnelighed**

Skriv `$SP/k10-maal.sql` og kør `psql -X -At -d $DB -f $SP/k10-maal.sql`. Det printer kun tal:

```sql
WITH r AS (SELECT id FROM private.source_persona_identity_candidate_run WHERE source_id=1 ORDER BY run_seq DESC LIMIT 1),
lb AS (  -- livsgrænser som §23.3 pkt. 1: afklarede konklusioner; NULL i en grænse ⇒ ukendt
  SELECT f.subjekt_id AS pid,
    CASE WHEN bool_or(a.date_min IS NULL) FILTER (WHERE f.faktatype='fødsel') THEN NULL ELSE min(a.date_min) FILTER (WHERE f.faktatype='fødsel') END AS bmin,
    CASE WHEN bool_or(a.date_max IS NULL) FILTER (WHERE f.faktatype='fødsel') THEN NULL ELSE max(a.date_max) FILTER (WHERE f.faktatype='fødsel') END AS bmax,
    CASE WHEN bool_or(a.date_min IS NULL) FILTER (WHERE f.faktatype='død') THEN NULL ELSE min(a.date_min) FILTER (WHERE f.faktatype='død') END AS dmin,
    CASE WHEN bool_or(a.date_max IS NULL) FILTER (WHERE f.faktatype='død') THEN NULL ELSE max(a.date_max) FILTER (WHERE f.faktatype='død') END AS dmax
    FROM fact f JOIN conclusion k ON k.target_type='fact' AND k.target_id=f.id AND k.status='afklaret'
    JOIN assertion a ON a.id=k.valgt_assertion_id
   WHERE f.subjekt_type='person' AND f.faktatype IN ('fødsel','død') GROUP BY 1),
e AS (SELECT c.source_persona_id AS sp, c.candidate_person_id AS p1,
             (private.persona_family_context(c.source_persona_id)->>'principal_person_id')::bigint AS hp
        FROM private.source_persona_identity_candidate c, r
       WHERE c.run_id=r.id AND c.rank=1 AND (c.basis->>'corroboration_eligible')::boolean),
imp AS (SELECT e.sp, coalesce(cl.dmax < pl.bmin OR cl.bmin > pl.dmax, false) AS r1_umulig
          FROM e LEFT JOIN lb pl ON pl.pid=e.hp LEFT JOIN lb cl ON cl.pid=e.p1),
hom AS (SELECT e.sp, count(c2.*) AS h
          FROM e JOIN person p1 ON p1.id=e.p1
          LEFT JOIN private.source_persona_identity_candidate c2 ON c2.run_id=(SELECT id FROM r) AND c2.source_persona_id=e.sp AND c2.rank BETWEEN 2 AND 10
          LEFT JOIN person p2 ON p2.id=c2.candidate_person_id
          LEFT JOIN lb pl ON pl.pid=e.hp LEFT JOIN lb cl ON cl.pid=c2.candidate_person_id
         WHERE c2.id IS NULL OR ((lower(btrim(p2.visning_navn))=lower(btrim(p1.visning_navn))
                OR lower(btrim(p2.visning_fuldt_navn))=lower(btrim(p1.visning_fuldt_navn)))
               AND NOT coalesce(cl.dmax < pl.bmin OR cl.bmin > pl.dmax, false))
         GROUP BY e.sp)
SELECT 'egnede', count(*),
       'r1_umulig', count(*) FILTER (WHERE imp.r1_umulig),
       'h1', count(*) FILTER (WHERE hom.h=1), 'h2', count(*) FILTER (WHERE hom.h=2), 'h_over2', count(*) FILTER (WHERE hom.h>2)
  FROM e JOIN imp USING (sp) JOIN hom USING (sp);
```

Expected: én linje med tal. Ledger: `Task 11: egnede=… r1_umulig=… navnefaeller h1=… h2=… h_over2=…`.

- [ ] **Step 3: Skelnelighed for navnefællekort (kun tal)**

For navnefælle-personas med h=1 eller h=2 tælles, hvor mange hvis rang 1 og navnefæller **alle** adskiller sig parvist på mindst ét af: `visning_foedt`, `visning_doed`, egen postnøgle og mængden af forældre-id'er. Tilføj til `$SP/k10-maal.sql` (samme CTE'er):

```sql
, shown AS (
  SELECT e.sp, x.cand AS pid FROM e CROSS JOIN LATERAL (
    SELECT e.p1 AS cand UNION
    SELECT c2.candidate_person_id FROM private.source_persona_identity_candidate c2 JOIN person p2 ON p2.id=c2.candidate_person_id
      JOIN person p1 ON p1.id=e.p1
     WHERE c2.run_id=(SELECT id FROM r) AND c2.source_persona_id=e.sp AND c2.rank BETWEEN 2 AND 10
       AND (lower(btrim(p2.visning_navn))=lower(btrim(p1.visning_navn)) OR lower(btrim(p2.visning_fuldt_navn))=lower(btrim(p1.visning_fuldt_navn)))) x),
sig AS (SELECT s.sp, s.pid, concat_ws('|', p.visning_foedt, p.visning_doed,
          (SELECT string_agg(fp.person_id::text, ',' ORDER BY fp.person_id) FROM family_member fb
             JOIN family_member fp ON fp.family_id=fb.family_id AND fp.rolle='partner' WHERE fb.person_id=s.pid AND fb.rolle='barn')) AS k
          FROM shown s JOIN person p ON p.id=s.pid)
SELECT 'navnefaellekort', count(DISTINCT sp),
       'skelnelige', count(DISTINCT sp) FILTER (WHERE sp IN (SELECT sp FROM sig GROUP BY sp HAVING count(DISTINCT k)=count(*)))
  FROM sig WHERE sp IN (SELECT sp FROM hom WHERE h BETWEEN 1 AND 2);
```

Expected: to tal. (Egen postnøgle er udeladt af signaturen. Det gør tallet konservativt, så det rapporterer færre skelnelige kort.) Er `skelnelige` < `navnefaellekort`, ledges tallet og forskellen. Kort, der ikke kan skelnes, er netop dem, hvor projektejerens ærlige svar er `U` ⇒ `failed`. Stop og vis projektejeren tallet, før Task 12 begynder, hvis mere end 2 navnefællekort ikke kan skelnes. Ved 0–2 fortsættes, med en ledger-note om, at disse kort kan gøre kørslen `failed`.

---

### Task 12: Kontrolkørsel v2 i databasen

**Files:**
- Modify: `schema.sql` (5b-sektionen: tabeller 15276-15334, `control_run_status` 15368-15416, `red_register_identity_control_run` 15418-15484, `check_family_corroboration` (d) 15629-15636, `red_corroborate_family_identities` 15662-15669, `red_afgoer_relation_interpretation` ~15186-15275)
- Modify: `db-migrations.sql` (samme funktioner i 5b-sektionen sidst i filen + idempotente ALTERs for eksisterende baser; ny RPC i `v_authenticated` og `$public_red_revoke$`-listen som `to_regprocedure`)
- Modify: `db-rls.sql` (allow-list + master-array: `red_classify_parent_card(uuid,uuid,integer,text,text,jsonb)`)
- Modify: `db-verify.sql` (`$identity_control_verify$`: de tre nye tabeller; ACL-listen)
- Test: `tests/sql/test-identity-control-run.sql`, `tests/sql/test-relation-decision.sql`, `tests/sql/test-family-corroboration.sql`

**Interfaces:**
- Produces (bruges af Task 13 og 14):
  - `private.identity_control_exclusion(control_run_id uuid, source_persona_id uuid, reason text)` — reason ∈ `rang1_tidsumulig`, `navnefaeller_over_3`.
  - `private.identity_control_parent_card(id uuid, control_run_id uuid, interpretation_key uuid, interpretation_version int, family_id bigint, counterpart_person_id bigint, counterpart_persona_id uuid, partner_ids bigint[])`.
  - `private.identity_control_parent_event(card_id uuid, seq int, outcome text, note text, sheet_sha256 text, rows_sha256 text, line int, created_by uuid, created_at timestamptz)` — outcome ∈ `F`, `familie_aendret`.
  - `identity_control_run.excluded_sha256 text`, `identity_control_run.k_random integer`; `relation_population_sha256` = hash af forældrekortenes sorterede nøgler.
  - `identity_control_sample.stratum` ∈ `single_family`, `multi_family`, `navnefaelle`, `relation` (sidste kun historisk).
  - `private.person_life_bounds(bigint) → TABLE(birth_min date, birth_max date, death_min date, death_max date)`.
  - `private.candidate_impossible(p_principal bigint, p_candidate bigint) → boolean`.
  - `private.control_allocate(p_counts jsonb, p_k integer) → jsonb` (stratum → antal).
  - `red_classify_parent_card(p_control_run_id uuid, p_interpretation_key uuid, p_expected_version integer, p_outcome text, p_note text, p_context jsonb) → integer` (event-seq).
  - `red_afgoer_relation_interpretation(...)`: uændret signatur; `p_action` ∈ `same`, `unresolved`, `rejected`. Med `p_context.control_run_id` gælder forældrekortvejen: serveren opløser familien, og returværdien er 0, når der i stedet skrives `familie_aendret`.

- [ ] **Step 1: Skriv de fejlende tests (identitet)**

I `tests/sql/test-identity-control-run.sql`, efter de eksisterende blokke, tilføj en blok `$control_v2$` med en egen verden (kilde `-5701`). Brug `pg_temp.f5b_control_world`'s mønster: 5 hovedposter, hver med én ægteskabspåstand, ægtefælle-persona og familie. Tilføj en hjælper til leveår:

```sql
CREATE FUNCTION pg_temp.f5b_life(p_person bigint,p_born int,p_died int) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_f bigint; v_a bigint;
BEGIN
  IF p_born IS NOT NULL THEN
    INSERT INTO fact(subjekt_type,subjekt_id,faktatype) VALUES ('person',p_person,'fødsel') RETURNING id INTO v_f;
    INSERT INTO assertion(target_type,target_id,date_min,date_max) VALUES ('fact',v_f,make_date(p_born,1,1),make_date(p_born,12,31)) RETURNING id INTO v_a;
    INSERT INTO conclusion(target_type,target_id,valgt_assertion_id,status) VALUES ('fact',v_f,v_a,'afklaret');
  END IF;
  IF p_died IS NOT NULL THEN
    INSERT INTO fact(subjekt_type,subjekt_id,faktatype) VALUES ('person',p_person,'død') RETURNING id INTO v_f;
    INSERT INTO assertion(target_type,target_id,date_min,date_max) VALUES ('fact',v_f,make_date(p_died,1,1),make_date(p_died,12,31)) RETURNING id INTO v_a;
    INSERT INTO conclusion(target_type,target_id,valgt_assertion_id,status) VALUES ('fact',v_f,v_a,'afklaret');
  END IF;
END $$;
```

(Kolonnerne i `fact`/`assertion`/`conclusion` kan kræve flere NOT NULL-felter. Udfyld dem efter `schema.sql`'s CREATE TABLE og ledger en `Ruling:`, hvis hjælperen må afvige.)

Verden (hovedperson H_i født 1700, død 1760, ægtefælle-kandidat M_i som eneste partner, rang 1):

| i | rang 1 (M_i) | rang 2 | forventet |
|---|---|---|---|
| 1 | M1 1705–1770 | ingen | stratum single_family |
| 2 | M2 1705–1770 | N2: samme `visning_navn` som M2, 1710–1780 | stratum `navnefaelle`, mapping har 2 pladser |
| 3 | M3 død 1363 (født NULL) | ingen | udelukket `rang1_tidsumulig` |
| 4 | M4 1705–1770 | N4a, N4b, N4c: samme navn | udelukket `navnefaeller_over_3` |
| 5 | M5 uden datoer | X5: død 1363, andet navn | stratum single_family; X5 ikke i mappingen |

Assertions efter `red_register_identity_control_run`:

```sql
IF (SELECT count(*) FROM private.identity_control_sample WHERE control_run_id=v_ctl)<>3
   OR (SELECT stratum FROM private.identity_control_sample WHERE control_run_id=v_ctl AND source_persona_id=v_p[2])<>'navnefaelle'
   OR (SELECT count(*) FROM jsonb_object_keys((SELECT mapping FROM private.identity_control_sample WHERE control_run_id=v_ctl AND source_persona_id=v_p[2])))<>2
   OR (SELECT reason FROM private.identity_control_exclusion WHERE control_run_id=v_ctl AND source_persona_id=v_p[3])<>'rang1_tidsumulig'
   OR (SELECT reason FROM private.identity_control_exclusion WHERE control_run_id=v_ctl AND source_persona_id=v_p[4])<>'navnefaeller_over_3'
   OR EXISTS (SELECT 1 FROM private.identity_control_sample s, jsonb_each_text(s.mapping) m
               JOIN private.source_persona_identity_candidate c ON c.id=m.value::uuid
              WHERE s.control_run_id=v_ctl AND c.candidate_person_id=v_x5) THEN
  RAISE EXCEPTION 'CONTROL_V2_TEST_FAILED: udvalg/udelukkelse/projektion';
END IF;
```

Plus, i samme blok:
- `private.control_allocate('{"single_family":150,"multi_family":42}',20)` = `{"single_family":16,"multi_family":4}`; `('{"a":1,"b":100}',3)` = `{"a":1,"b":2}`; `('{"a":2,"b":1}',20)` = `{"a":2,"b":1}`; `('{"single_family":5,"multi_family":5}',3)` = `{"multi_family":2,"single_family":1}` (kvoter 1,5/1,5 → 1/1; den sidste plads går ved lige rest til stratumnavnet først i alfabetet).
- `private.candidate_impossible(H1, X)` for X uden datoer = `false`; for X død 1363 = `true`; for H uden datoer og X død 1363 = `false`.
- Navnefælle med `visning_fuldt_navn` NULL på begge: kun `visning_navn` afgør (variant af i=2 med NULL fuldt navn i en ekstra persona; forventet `navnefaelle`).
- Efter forsegling + korrekte afgørelser af de 3 stikprøvesager ⇒ `passed`; `red_corroborate_family_identities` med mængde-hashen over (egnede uden for stikprøven **og** uden for udelukkelsen) returnerer 0 nye her (alle andre er udelukket eller i stikprøven), og et direkte kernekald for v_p[3] med kontrolkørslens id afvises med `FAMILY_CORROBORATION_CONTROL_NOT_PASSED`.

- [ ] **Step 2: Skriv de fejlende tests (forældrekort)**

I `tests/sql/test-relation-decision.sql`: tilføj en blok `$parent_card$` med to hovedposter (forælder P, barn B), B som `barn` i P's familie, en `relation.parent`-påstand i B's post, en ægtefælle-persona med rang-1-kandidat (så kontrolkørslen kan registreres) og en kandidatkørsel. Assertions:

```sql
-- registrering gemmer ét forældrekort med familie, modpart og partnermængde
IF (SELECT count(*) FROM private.identity_control_parent_card WHERE control_run_id=v_ctl)<>1
   OR (SELECT family_id FROM private.identity_control_parent_card WHERE control_run_id=v_ctl)<>v_fam THEN
  RAISE EXCEPTION 'PARENT_CARD_TEST_FAILED: registrering';
END IF;
-- forsegling, derefter A uden familie fra klienten → accepted med parent-part
PERFORM red_seal_identity_control_run(v_ctl,repeat('a',64),repeat('b',64));
v_ver:=red_afgoer_relation_interpretation(v_key,1,'same',NULL,'A',jsonb_build_object('basis','human_sheet',
  'sheet_sha256',repeat('a',64),'rows_sha256',repeat('b',64),'line',3,'control_run_id',v_ctl));
-- forkert arkhash → PARENT_CARD_CONTEXT_INVALID; klientleveret familie → PARENT_CARD_CONTEXT_INVALID
-- R på et andet kort → status rejected, ingen parent-part
-- F → red_classify_parent_card returnerer 1, påstanden stadig proposed
-- A efter at en ny familie med B som barn og en anden hovedperson som partner er tilføjet → returnerer 0,
--   event 'familie_aendret', påstanden stadig proposed
-- kontrolkørslens status er uændret af alle forældreafgørelser (not_ready før identitetsafgørelsen)
```

Skriv hver kommentar ovenfor som en `BEGIN … EXCEPTION`-blok eller IF-assert i samme stil som de eksisterende tests i filen. Den eksisterende blok `$relation_decision$` (web-vejen med `p_family_id`) bevares og får én ekstra assert: `rejected` virker også uden kort.

- [ ] **Step 3: Kør testene og se dem fejle**

```bash
cd <worktree>; dropdb --if-exists ci5b_v2; createdb ci5b_v2
for f in tests/sql/evidence-promotion-bootstrap.sql schema.sql db-rls.sql db-migrations.sql db-migrations.sql db-rls.sql; do
  PGDATABASE=ci5b_v2 psql -X -q -v ON_ERROR_STOP=1 -f $f >/dev/null 2>$SP/v2-setup.err || { echo FAIL $f; tail -3 $SP/v2-setup.err; break; }; done
for t in test-identity-control-run test-relation-decision; do
  PGDATABASE=ci5b_v2 psql -X -q -v ON_ERROR_STOP=1 -f tests/sql/$t.sql 2>&1 | grep -E "OK:|ERROR|FAILED" | head -5; done
```
Expected: FAIL. Fx `relation "private.identity_control_exclusion" does not exist` eller `function private.control_allocate(…) does not exist`.

- [ ] **Step 4: Tabeller og hjælpere (schema.sql og db-migrations.sql)**

Efter `identity_control_event` (begge filer; i migrations med `IF NOT EXISTS` og idempotente ALTERs):

```sql
ALTER TABLE private.identity_control_run ADD COLUMN IF NOT EXISTS excluded_sha256 text
  CHECK (excluded_sha256 IS NULL OR excluded_sha256 ~ '^[0-9a-f]{64}$');
ALTER TABLE private.identity_control_run ADD COLUMN IF NOT EXISTS k_random integer CHECK (k_random IS NULL OR k_random>=0);
ALTER TABLE private.identity_control_sample DROP CONSTRAINT IF EXISTS identity_control_sample_stratum_check;
ALTER TABLE private.identity_control_sample ADD CONSTRAINT identity_control_sample_stratum_check
  CHECK (stratum IN ('single_family','multi_family','navnefaelle','relation'));
CREATE TABLE IF NOT EXISTS private.identity_control_exclusion (
  control_run_id    uuid NOT NULL REFERENCES private.identity_control_run(id),
  source_persona_id uuid NOT NULL REFERENCES private.source_persona(id),
  reason            text NOT NULL CHECK (reason IN ('rang1_tidsumulig','navnefaeller_over_3')),
  PRIMARY KEY (control_run_id,source_persona_id)
);
CREATE TABLE IF NOT EXISTS private.identity_control_parent_card (
  id                     uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  control_run_id         uuid NOT NULL REFERENCES private.identity_control_run(id),
  interpretation_key     uuid NOT NULL,
  interpretation_version integer NOT NULL CHECK (interpretation_version>=1),
  family_id              bigint NOT NULL,
  counterpart_person_id  bigint NOT NULL,
  counterpart_persona_id uuid NOT NULL REFERENCES private.source_persona(id),
  partner_ids            bigint[] NOT NULL,
  UNIQUE (control_run_id,interpretation_key)
);
CREATE TABLE IF NOT EXISTS private.identity_control_parent_event (
  card_id      uuid NOT NULL REFERENCES private.identity_control_parent_card(id),
  seq          integer NOT NULL CHECK (seq>=1),
  outcome      text NOT NULL CHECK (outcome IN ('F','familie_aendret')),
  note         text NOT NULL CHECK (btrim(note)<>''),
  sheet_sha256 text NOT NULL CHECK (sheet_sha256 ~ '^[0-9a-f]{64}$'),
  rows_sha256  text NOT NULL CHECK (rows_sha256 ~ '^[0-9a-f]{64}$'),
  line         integer NOT NULL CHECK (line>=1),
  created_by   uuid NOT NULL,
  created_at   timestamptz NOT NULL DEFAULT clock_timestamp(),
  PRIMARY KEY (card_id,seq)
);
```
I schema.sql: tilføj kolonnerne direkte i `CREATE TABLE private.identity_control_run`, og ret `stratum`-CHECK'en i `identity_control_sample` til at give constraintnavnet `identity_control_sample_stratum_check` (Postgres' autonavn, så migrationens DROP rammer det). Udvid `$identity_control_tables$`-løkkens array med de tre nye tabeller (append-only-triggere, RLS, REVOKE).

Hjælpere (begge filer):

```sql
-- §23.3 pkt. 1: livsgrænser fra matcherens data (afklarede konklusioner); en NULL-grænse ⇒ ukendt.
CREATE OR REPLACE FUNCTION private.person_life_bounds(p_person bigint)
RETURNS TABLE(birth_min date,birth_max date,death_min date,death_max date)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public AS $$
  SELECT CASE WHEN bool_or(a.date_min IS NULL) FILTER (WHERE f.faktatype='fødsel') THEN NULL ELSE min(a.date_min) FILTER (WHERE f.faktatype='fødsel') END,
         CASE WHEN bool_or(a.date_max IS NULL) FILTER (WHERE f.faktatype='fødsel') THEN NULL ELSE max(a.date_max) FILTER (WHERE f.faktatype='fødsel') END,
         CASE WHEN bool_or(a.date_min IS NULL) FILTER (WHERE f.faktatype='død') THEN NULL ELSE min(a.date_min) FILTER (WHERE f.faktatype='død') END,
         CASE WHEN bool_or(a.date_max IS NULL) FILTER (WHERE f.faktatype='død') THEN NULL ELSE max(a.date_max) FILTER (WHERE f.faktatype='død') END
    FROM public.fact f JOIN public.conclusion k ON k.target_type='fact' AND k.target_id=f.id AND k.status='afklaret'
    JOIN public.assertion a ON a.id=k.valgt_assertion_id
   WHERE f.subjekt_type='person' AND f.subjekt_id=p_person AND f.faktatype IN ('fødsel','død');
$$;
-- Definitivt umulig: kandidaten døde før hovedpersonen blev født, eller blev født efter hovedpersonens død.
CREATE OR REPLACE FUNCTION private.candidate_impossible(p_principal bigint,p_candidate bigint)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,private AS $$
  SELECT coalesce(c.death_max<p.birth_min OR c.birth_min>p.death_max,false)
    FROM private.person_life_bounds(p_principal) p,private.person_life_bounds(p_candidate) c;
$$;
-- §23.3 pkt. 4: præcis min(K, N) fordelt med største rest; mindst ét pr. ikke-tomt stratum; lige rester → stratumnavn.
CREATE OR REPLACE FUNCTION private.control_allocate(p_counts jsonb,p_k integer)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE v_n integer; v_k integer; v_out jsonb:='{}'; v_sum integer; r record;
BEGIN
  SELECT coalesce(sum(value::integer),0) INTO v_n FROM jsonb_each_text(p_counts) WHERE value::integer>0;
  v_k:=least(p_k,v_n);
  IF v_k<=0 THEN RETURN '{}'::jsonb; END IF;
  FOR r IN SELECT key,value::integer AS n FROM jsonb_each_text(p_counts) WHERE value::integer>0 LOOP
    v_out:=v_out||jsonb_build_object(r.key,least(r.n,greatest(1,floor(v_k::numeric*r.n/v_n)::integer)));
  END LOOP;
  SELECT sum(value::integer) INTO v_sum FROM jsonb_each_text(v_out);
  WHILE v_sum<v_k LOOP
    SELECT key INTO r FROM jsonb_each_text(p_counts) c
     WHERE value::integer>(v_out->>key)::integer
     ORDER BY (v_k::numeric*value::integer/v_n)-(v_out->>key)::integer DESC,key LIMIT 1;
    v_out:=jsonb_set(v_out,ARRAY[r.key],to_jsonb((v_out->>r.key)::integer+1)); v_sum:=v_sum+1;
  END LOOP;
  WHILE v_sum>v_k LOOP
    SELECT key INTO r FROM jsonb_each_text(v_out) WHERE value::integer>1 ORDER BY value::integer DESC,key LIMIT 1;
    v_out:=jsonb_set(v_out,ARRAY[r.key],to_jsonb((v_out->>r.key)::integer-1)); v_sum:=v_sum-1;
  END LOOP;
  RETURN v_out;
END $$;
REVOKE ALL ON FUNCTION private.person_life_bounds(bigint),private.candidate_impossible(bigint,bigint),
  private.control_allocate(jsonb,integer) FROM PUBLIC,anon,authenticated;
```

- [ ] **Step 5: `red_register_identity_control_run` v2 (begge filer)**

Erstat alt fra `-- DROP før CTAS` til `RETURN v_id;` med:

```sql
  DROP TABLE IF EXISTS pg_temp.ctl_elig, pg_temp.ctl_ipop, pg_temp.ctl_excl, pg_temp.ctl_cards;
  -- egnede, uafgjorte rang-1-personas med hovedperson og rang-1-person
  CREATE TEMP TABLE pg_temp.ctl_elig ON COMMIT DROP AS
    SELECT c.source_persona_id AS pid,c.id AS cand_id,c.candidate_person_id AS p1,coalesce(i.version,0) AS ver,
           private.spouse_principal_person(c.source_persona_id) AS hp,
           CASE WHEN jsonb_array_length(private.persona_family_context(c.source_persona_id)->'families')=1
                THEN 'single_family' ELSE 'multi_family' END AS fam_stratum,
           encode(extensions.digest(convert_to(p_candidate_run_id::text||':'||c.source_persona_id::text,'UTF8'),'sha256'),'hex') AS h
      FROM private.source_persona_identity_candidate c
      LEFT JOIN private.source_persona_identity i ON i.source_persona_id=c.source_persona_id
     WHERE c.run_id=p_candidate_run_id AND c.rank=1 AND (c.basis->>'corroboration_eligible')::boolean IS TRUE
       AND (i.source_persona_id IS NULL OR i.decision_status='proposed');
  -- navnefæller: andre gemte kandidater (rang ≤ 10), ikke umulige, med samme visningsnavn eller fulde navn
  ALTER TABLE pg_temp.ctl_elig ADD COLUMN homs uuid[];
  UPDATE pg_temp.ctl_elig e SET homs=coalesce((
    SELECT array_agg(c2.id ORDER BY c2.rank) FROM private.source_persona_identity_candidate c2
      JOIN public.person p2 ON p2.id=c2.candidate_person_id JOIN public.person p1 ON p1.id=e.p1
     WHERE c2.run_id=p_candidate_run_id AND c2.source_persona_id=e.pid AND c2.rank>1
       AND NOT private.candidate_impossible(e.hp,c2.candidate_person_id)
       AND (lower(btrim(p2.visning_navn))=lower(btrim(p1.visning_navn))
            OR lower(btrim(p2.visning_fuldt_navn))=lower(btrim(p1.visning_fuldt_navn)))),'{}');
  CREATE TEMP TABLE pg_temp.ctl_excl ON COMMIT DROP AS
    SELECT pid,CASE WHEN private.candidate_impossible(hp,p1) THEN 'rang1_tidsumulig' ELSE 'navnefaeller_over_3' END AS reason
      FROM pg_temp.ctl_elig WHERE private.candidate_impossible(hp,p1) OR cardinality(homs)>2;
  CREATE TEMP TABLE pg_temp.ctl_ipop ON COMMIT DROP AS
    SELECT e.*,CASE WHEN cardinality(e.homs)>0 THEN 'navnefaelle' ELSE e.fam_stratum END AS stratum
      FROM pg_temp.ctl_elig e WHERE e.pid NOT IN (SELECT pid FROM pg_temp.ctl_excl);
  -- forældrekort: gældende relation.parent med præcis én strukturel kandidatrække (én familie og én modpart)
  CREATE TEMP TABLE pg_temp.ctl_cards ON COMMIT DROP AS
    SELECT ic.interpretation_key AS k,ic.version AS v,min(sc.family_id) AS fam,min(sc.counterpart_person_id) AS cp,
           min(sc.counterpart_persona_id::text)::uuid AS cpp
      FROM private.interpretation_current ic
      CROSS JOIN LATERAL private.relation_structural_candidates(ic.interpretation_key) sc
     WHERE ic.source_id=v_source AND ic.predicate='relation.parent' AND ic.status='proposed'
     GROUP BY ic.interpretation_key,ic.version HAVING count(*)=1;
  SELECT private.reimport_canonical_json_sha256(coalesce(jsonb_agg(pid::text ORDER BY pid::text COLLATE "C"),'[]'::jsonb)) INTO v_ipop FROM pg_temp.ctl_ipop;
  SELECT private.reimport_canonical_json_sha256(coalesce(jsonb_agg(k::text ORDER BY k::text COLLATE "C"),'[]'::jsonb)) INTO v_rpop FROM pg_temp.ctl_cards;
  SELECT private.reimport_canonical_json_sha256(coalesce(jsonb_agg(pid::text ORDER BY pid::text COLLATE "C"),'[]'::jsonb)) INTO v_excl FROM pg_temp.ctl_excl;
  INSERT INTO private.identity_control_run(id,source_id,candidate_run_id,identity_population_sha256,relation_population_sha256,
    input_list_sha256,excluded_sha256,k_random,created_by)
    VALUES (v_id,v_source,p_candidate_run_id,v_ipop,v_rpop,private.control_input_list_sha256(p_candidate_run_id),v_excl,20,auth.uid());
  INSERT INTO private.identity_control_exclusion(control_run_id,source_persona_id,reason) SELECT v_id,pid,reason FROM pg_temp.ctl_excl;
  INSERT INTO private.identity_control_parent_card(control_run_id,interpretation_key,interpretation_version,family_id,
    counterpart_person_id,counterpart_persona_id,partner_ids)
  SELECT v_id,k,v,fam,cp,cpp,(SELECT array_agg(fm.person_id ORDER BY fm.person_id) FROM public.family_member fm
                               WHERE fm.family_id=fam AND fm.rolle='partner') FROM pg_temp.ctl_cards;
  -- stikprøve: alle navnefæller + K=20 tilfældige fordelt med største rest (spec §23.3)
  v_alloc:=private.control_allocate((SELECT coalesce(jsonb_object_agg(stratum,n),'{}') FROM (
      SELECT stratum,count(*) AS n FROM pg_temp.ctl_ipop WHERE stratum<>'navnefaelle' GROUP BY stratum) s),20);
  INSERT INTO private.identity_control_sample(control_run_id,sample_kind,stratum,source_persona_id,identity_version,mapping,expected)
  SELECT v_id,'identity',x.stratum,x.pid,x.ver,
         (SELECT jsonb_object_agg(m.pos::text,m.cid::text) FROM (
            SELECT d.cid,row_number() OVER (ORDER BY encode(extensions.digest(convert_to(v_id::text||':'||d.cid::text,'UTF8'),'sha256'),'hex')) AS pos
              FROM (SELECT cid FROM (
                      SELECT x.cand_id AS cid,0 AS pri,1 AS rk
                      UNION ALL SELECT h.cid,1,h.o FROM unnest(x.homs) WITH ORDINALITY h(cid,o)
                      UNION ALL SELECT c2.id,2,c2.rank FROM private.source_persona_identity_candidate c2
                       WHERE c2.run_id=p_candidate_run_id AND c2.source_persona_id=x.pid AND c2.rank>1
                         AND c2.id<>ALL(x.homs) AND NOT private.candidate_impossible(x.hp,c2.candidate_person_id)) u
                    ORDER BY pri,rk LIMIT 3) d) m),
         x.cand_id::text
    FROM (SELECT p.*,row_number() OVER (PARTITION BY p.stratum ORDER BY p.h) AS rn FROM pg_temp.ctl_ipop p) x
   WHERE x.stratum='navnefaelle' OR x.rn<=coalesce((v_alloc->>x.stratum)::integer,0);
  IF (SELECT count(*) FROM private.identity_control_sample WHERE control_run_id=v_id)>40 THEN
    RAISE EXCEPTION 'IDENTITY_CONTROL_SAMPLE_TOO_LARGE';
  END IF;
  RETURN v_id;
```
DECLARE tilføjer `v_excl text; v_alloc jsonb;`. `RAISE` efter INSERT ruller hele registreringen tilbage (transaktionen fejler), så intet efterlades.

- [ ] **Step 6: Status, kerne og bekræftelse**

`private.control_run_status`: erstat løkkens `FOR smp IN SELECT * … ORDER BY s.id LOOP` med `… WHERE s.control_run_id=r.id AND s.sample_kind='identity' ORDER BY s.id LOOP`, og fjern hele `ELSE`-grenen (relation), så løkken kun har identitetsgrenen + den fælles arkkontrol. Fjern `v_ic` fra DECLARE.

`private.check_family_corroboration` (d): tilføj før `THEN RAISE EXCEPTION 'FAMILY_CORROBORATION_CONTROL_NOT_PASSED'`:

```sql
     OR EXISTS (SELECT 1 FROM private.identity_control_exclusion x WHERE x.control_run_id=(p_evidence->>'control_run_id')::uuid
                 AND x.source_persona_id=p_persona)
```

`red_corroborate_family_identities`, `corr_set`: tilføj

```sql
       AND NOT EXISTS (SELECT 1 FROM private.identity_control_exclusion x WHERE x.control_run_id=p_control_run_id AND x.source_persona_id=c.source_persona_id)
```

- [ ] **Step 7: `red_afgoer_relation_interpretation` v2 og `red_classify_parent_card`**

I `red_afgoer_relation_interpretation` (begge filer):
- Tilladte `p_action`: `same`, `unresolved`, `rejected`. `p_family_id` kun ved `same` uden kort.
- Tilladte context-nøgler: `basis`, `sheet_sha256`, `rows_sha256`, `line`, `control_run_id` (`display_position` udgår).
- Fjern hele stikprøveblokken (`v_smp`/`v_seal` med `identity_control_sample` … `ELSIF v_ctx ? 'control_run_id' …`) og erstat den med kortvejen:

```sql
  IF v_ctx ? 'control_run_id' THEN
    SELECT * INTO v_card FROM private.identity_control_parent_card
     WHERE control_run_id=(v_ctx->>'control_run_id')::uuid AND interpretation_key=p_interpretation_key;
    SELECT * INTO v_seal FROM private.identity_control_event
     WHERE control_run_id=(v_ctx->>'control_run_id')::uuid AND status='sealed';
    IF v_card.id IS NULL OR v_seal.control_run_id IS NULL OR v_basis<>'human_sheet'
       OR v_ctx->>'sheet_sha256' IS DISTINCT FROM v_seal.sheet_sha256 OR v_ctx->>'rows_sha256' IS DISTINCT FROM v_seal.rows_sha256
       OR p_family_id IS NOT NULL OR p_action NOT IN ('same','rejected')
       OR p_expected_version IS DISTINCT FROM v_card.interpretation_version THEN
      RAISE EXCEPTION 'PARENT_CARD_CONTEXT_INVALID';
    END IF;
    v_family:=CASE WHEN p_action='same' THEN v_card.family_id END;
    v_evidence:=v_evidence||jsonb_build_object('control_run_id',v_card.control_run_id,'parent_card_id',v_card.id);
  ELSE
    v_family:=p_family_id;
    IF (p_action='same' AND v_family IS NULL) THEN RAISE EXCEPTION 'RELATION_DECISION_INVALID'; END IF;
  END IF;
```
- I `same`-grenen, efter `lock_family_rows`, for kortvejen: kræv præcis én kandidatrække **i alt**, lig kortets familie/modpart/partnermængde; ellers event i stedet for fejl:

```sql
    IF v_card.id IS NOT NULL AND (
         (SELECT count(*) FROM private.relation_structural_candidates(p_interpretation_key))<>1
      OR NOT EXISTS (SELECT 1 FROM private.relation_structural_candidates(p_interpretation_key) c
                      WHERE c.family_id=v_card.family_id AND c.counterpart_person_id=v_card.counterpart_person_id
                        AND c.counterpart_persona_id=v_card.counterpart_persona_id)
      OR (SELECT array_agg(fm.person_id ORDER BY fm.person_id) FROM public.family_member fm
           WHERE fm.family_id=v_card.family_id AND fm.rolle='partner') IS DISTINCT FROM v_card.partner_ids) THEN
      PERFORM private.append_parent_card_event(v_card.id,'familie_aendret',btrim(p_note),v_ctx);
      RETURN 0;
    END IF;
```
- `rejected`: `v_new:=public.red_decide_interpretation(v_ic.id,p_expected_version,'rejected',v_evidence);` (ingen part). `unresolved` som før.
- DECLARE: `v_card private.identity_control_parent_card%ROWTYPE` virker ikke, fordi tabellen oprettes efter funktionen i begge filer (plpgsql binder `%ROWTYPE` ved CREATE). Brug `v_card record` og initialisér med `SELECT NULL::uuid AS id INTO v_card;` før `IF`. Ledger det.

Nye funktioner (begge filer, efter tabellerne):

```sql
CREATE OR REPLACE FUNCTION private.append_parent_card_event(p_card uuid,p_outcome text,p_note text,p_ctx jsonb)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,private AS $$
DECLARE v_seq integer;
BEGIN
  SELECT coalesce(max(seq),0)+1 INTO v_seq FROM private.identity_control_parent_event WHERE card_id=p_card;
  INSERT INTO private.identity_control_parent_event(card_id,seq,outcome,note,sheet_sha256,rows_sha256,line,created_by)
  VALUES (p_card,v_seq,p_outcome,p_note,p_ctx->>'sheet_sha256',p_ctx->>'rows_sha256',(p_ctx->>'line')::integer,auth.uid());
  RETURN v_seq;
END $$;
REVOKE ALL ON FUNCTION private.append_parent_card_event(uuid,text,text,jsonb) FROM PUBLIC,anon,authenticated;

-- Spec §23.4: F — bogen siger det, men familien i basen passer ikke. Påstanden ændres ikke.
CREATE OR REPLACE FUNCTION red_classify_parent_card(p_control_run_id uuid,p_interpretation_key uuid,p_expected_version integer,
  p_outcome text,p_note text,p_context jsonb)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE v_card record; v_seal record;
BEGIN
  IF auth.uid() IS NULL OR public.current_rolle()<>'redaktion' THEN RAISE EXCEPTION 'EVIDENCE_ROLE_FORBIDDEN'; END IF;
  SELECT * INTO v_card FROM private.identity_control_parent_card WHERE control_run_id=p_control_run_id AND interpretation_key=p_interpretation_key;
  SELECT * INTO v_seal FROM private.identity_control_event WHERE control_run_id=p_control_run_id AND status='sealed';
  IF v_card.id IS NULL OR v_seal.control_run_id IS NULL OR p_outcome<>'F' OR nullif(btrim(p_note),'') IS NULL
     OR p_context->>'basis' IS DISTINCT FROM 'human_sheet'
     OR p_context->>'sheet_sha256' IS DISTINCT FROM v_seal.sheet_sha256 OR p_context->>'rows_sha256' IS DISTINCT FROM v_seal.rows_sha256
     OR coalesce(p_context->>'line','') !~ '^[1-9][0-9]*$' OR p_expected_version IS DISTINCT FROM v_card.interpretation_version THEN
    RAISE EXCEPTION 'PARENT_CARD_CONTEXT_INVALID';
  END IF;
  RETURN private.append_parent_card_event(v_card.id,'F',btrim(p_note),p_context);
END $$;
REVOKE ALL ON FUNCTION red_classify_parent_card(uuid,uuid,integer,text,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION red_classify_parent_card(uuid,uuid,integer,text,text,jsonb) TO authenticated;
```
ACL: tilføj `red_classify_parent_card(uuid,uuid,integer,text,text,jsonb)` **insert-only** (ingen omsortering) i db-rls' allow-list + master-array, db-migrations' `v_authenticated` og `$public_red_revoke$` (som `to_regprocedure('public.red_classify_parent_card(uuid,uuid,integer,text,text,jsonb)')`), og db-verify's ACL-liste. Udvid `$identity_control_verify$`-arrayet med de tre nye tabeller.

- [ ] **Step 8: Kør testene og se dem bestå**

Samme kommandoer som Step 3 på en frisk `ci5b_v2`.
Expected: alle `OK:`-linjer, inkl. de nye `$control_v2$`/`$parent_card$`-blokke; 0 `ERROR`. Kør også `tests/sql/test-family-corroboration.sql` og `tests/sql/run-db-verify-disposable.sql` (VERIFY_OK) på samme base. Drop `ci5b_v2` bagefter.

- [ ] **Step 9: Hele DB-CI og commit**

```bash
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql tests/sql/test-identity-control-run.sql tests/sql/test-relation-decision.sql tests/sql/test-family-corroboration.sql
for j in "writer-1939-v50-db 55431" "interpretation-proposal-db 55432" "narrative-record-contract-db 55433" "evidence-promotion-db 55434"; do
  /usr/bin/python3 $SP/localci.py $j > $SP/ci-${j%% *}.txt 2>&1 & done; wait; grep -h "rc=[^0]\|FAILS" $SP/ci-*.txt
git commit -m "feat(151): kontrolkørsel v2 — navnefæller, udelukkelse, forældrekort (spec §23)

Claude-Session: https://claude.ai/code/session_018KPNPJmdDmYBKcQQ14VfHb"
```
Expected: kun R-pakkeinstallationstrinnene fejler (intet CRAN-spejl lokalt); alle andre `rc=0`. Flyt CI's `*.out`/`*-catalog.json` fra worktree-roden til `$SP/ci-out/` før commit.

---

### Task 13: Rækkefil og kontrolark v2

**Files:**
- Modify: `.claude/skills/daa-extract/scripts/identity_control_rows.sql` (hele filen)
- Modify: `.claude/skills/daa-extract/scripts/identity_control_sheet.py` (render/parse/sql; `split_rows` og `MAX_LINES` udgår)
- Test: `.claude/skills/daa-extract/scripts/test_identity_control_sheet.py` (omskrives)

**Interfaces:**
- Consumes: Task 12's tabeller (`identity_control_sample` med mapping, `identity_control_parent_card`), `private.spouse_principal_person`.
- Produces: rækkefil-JSON:
  ```json
  {"control_run_id": "…", "candidate_run_id": "…", "k_random": 20, "items": [
    {"kind": "identity", "source_persona_id": "…", "version": 0, "record_key": "I-1", "pages": "12",
     "principal": {"name": "…", "born": "…", "died": "…"}, "marriage_ordinal": 1,
     "observation_id": "…", "text_sha256": "…", "text": "…", "span": [10, 19],
     "display": [{"position": 1, "candidate_id": "…", "name": "…", "born": "…", "died": "…",
                  "titles": ["…"], "own_post_key": "II-9", "parents": [{"name": "…", "born": "…", "died": "…"}]}]},
    {"kind": "parent", "interpretation_key": "…", "version": 1, "record_key": "I-17", "pages": "40",
     "principal": {…}, "observation_id": "…", "text_sha256": "…", "text": "…",
     "family_id": 11, "partners": [{"name": "…", "born": "…", "died": "…", "own_post_key": "I-10", "counterpart": true}]}]}
  ```
  `identity_control_sheet.py render|sql` med samme CLI som i dag, minus `--part`.

- [ ] **Step 1: Skriv de fejlende Python-tests**

Erstat `test_identity_control_sheet.py`'s fixture med en rækkefil i formatet ovenfor: to identitetskort (ét med 2 kandidater og forældre, ét med 1 kandidat), ét forældrekort med 2 partnere, hvoraf den ene er `counterpart`. Testene:

```python
def test_render_viser_hovedperson_klausul_spaend_og_forældre(self):
    txt = render_sheet(ROWS)
    self.assertIn("#   Hovedperson: Hoved Et (1700–1760)", txt)
    self.assertIn("#   Bogen: »Gift 1725 med [[Anna Berg]], f. 1705.«", txt)
    self.assertIn("#        forældre: Carl Berg (1670–1730), Maria Berg (?–?)", txt)
    self.assertNotIn("score", txt); self.assertNotIn("familie 1", txt); self.assertNotIn("person 2", txt)

def test_render_normaliserer_whitespace_i_klausul(self):
    rows = deepcopy(ROWS); rows["items"][0]["text"] = "Gift 1725\nD med [[x]]  #y"; rows["items"][0]["span"] = None
    txt = render_sheet(rows)
    self.assertIn("#   Bogen: »Gift 1725 D med [[x]] #y«", txt)
    self.assertEqual(len([l for l in txt.splitlines() if l.startswith("D ")]), 2)

def test_forældrekort_viser_modpart_og_begge_forældre(self):
    txt = render_sheet(ROWS)
    self.assertIn("#   Familie: Carl Berg (1670–1730) · egen post I-10 ← modpart; Maria Berg (?–?)", txt)
    self.assertIn("R " + KEY + " 1 : _", txt)

def test_parse_tokens(self):
    ok = render_sheet(ROWS).replace(" : _", " : 1", 1).replace(" : _", " : X", 1).replace(" : _", " : F", 1)
    self.assertEqual([l.tok for l in parse_sheet(ok)], ["1", "X", "F"])
    for bad in ("P 5", "2", "A"):   # P findes ikke; D-linje med A ugyldig
        with self.assertRaises(SheetError): parse_sheet(render_sheet(ROWS).replace(" : _", f" : {bad}", 1).replace(" : _", " : U"))

def test_sql_to_transaktioner_og_forældre_efter_evaluering(self):
    sql = decision_sql(LINES_ALL, ROWS, sheet_sha256="a"*64, rows_sha256="b"*64)
    t1, t2 = sql.split("COMMIT;")[:2]
    self.assertIn("red_seal_identity_control_run", t1); self.assertIn("red_evaluate_identity_control_run", t1)
    self.assertNotIn("red_afgoer_relation_interpretation", t1)
    self.assertIn("red_classify_parent_card", t2)           # F
    self.assertNotIn("display_position", t2)
    self.assertIn('"control_run_id"', t2); self.assertIn("'same', NULL", t2)   # A: serveren opløser familien

def test_sql_U_på_forælder_skriver_intet(self):
    sql = decision_sql(LINES_PARENT_U, ROWS, sheet_sha256="a"*64, rows_sha256="b"*64)
    t2 = sql.split("COMMIT;")[1]
    self.assertNotIn("red_afgoer_relation_interpretation", t2); self.assertNotIn("red_classify_parent_card", t2)
```
Behold de eksisterende tests for hashbinding, `SHEET_UNDECIDED`, `SHEET_DUPLICATE`, `SHEET_RENDER_MISMATCH` og `SHEET_IDENTITY_MISMATCH`, tilpasset fixturen. Fjern tests for `split_rows`, `P <id>` og R-linjer med `1-3`.

- [ ] **Step 2: Kør og se dem fejle**

Run: `env -u NODE_OPTIONS /usr/bin/python3 -m pytest -q .claude/skills/daa-extract/scripts/test_identity_control_sheet.py`
Expected: FAIL (fx `KeyError: 'principal'`, eller at de forventede strenge ikke findes).

- [ ] **Step 3: Implementér `identity_control_sheet.py` v2**

Erstat regex'er, render, parse og `decision_sql`:

```python
D_RE = re.compile(rf"^D (?P<id>{UUID}) (?P<ver>[0-9]+) : (?P<tok>_|[123]|X|N|U)\s*(?:#\s*(?P<note>.*))?$")
R_RE = re.compile(rf"^R (?P<id>{UUID}) (?P<ver>[0-9]+) : (?P<tok>_|A|R|F|U)\s*(?:#\s*(?P<note>.*))?$")

def _ws(s: str | None) -> str:
    return " ".join((s or "").split())

def _years(p: dict) -> str:
    return f"{p.get('born') or '?'}–{p.get('died') or '?'}"

def _clause(it: dict) -> str:
    t = it["text"]
    if it.get("span"):
        a, b = it["span"]; t = t[:a] + "[[" + t[a:b] + "]]" + t[b:]
    return f"#   Bogen: »{_ws(t)}«"

def _key(it: dict) -> tuple:
    return (0 if it["kind"] == "identity" else 1, it["record_key"], it.get("source_persona_id") or it["interpretation_key"])

def ordered(rows: dict) -> list[dict]:
    return sorted(rows["items"], key=_key)

def render_sheet(rows: dict) -> str:
    out = ["# KONTROLARK (trin 5b del 1)",
           "# Ægtefællekort (D): 1/2/3 = samme person som kandidat nr., X = ingen af dem, N = ny person nødvendig, U = kan ikke afgøres.",
           "# Forældrekort (R): A = sandt, R = bogen siger ikke dette, F = bogen siger det, men familien i basen passer ikke, U = kan ikke afgøres.",
           "# Afgør ud fra bogen. En note må følge efter '#'. Ret intet andet. Gem, og giv hashen i chatten.", ""]
    items = ordered(rows); n_d = sum(1 for i in items if i["kind"] == "identity"); n_r = len(items) - n_d
    d = r = 0
    for it in items:
        p = it["principal"]
        if it["kind"] == "identity":
            d += 1
            out.append(f"## ÆGTEFÆLLEKORT {d}/{n_d} · post {it['record_key']} · PDF-side {it['pages']} · ægteskab nr. {it['marriage_ordinal']}")
            out.append(f"#   Hovedperson: {_ws(p['name']) or '(intet navn)'} ({_years(p)})")
            out.append(_clause(it))
            for c in sorted(it["display"], key=lambda c: c["position"]):
                t = f"  · {', '.join(_ws(x) for x in c['titles'])}" if c["titles"] else ""
                post = f"  · egen post {c['own_post_key']}" if c["own_post_key"] else ""
                out.append(f"#   {c['position']}: {_ws(c['name']) or '(intet navn)'} ({_years(c)}){t}{post}")
                if c["parents"]:
                    out.append("#        forældre: " + ", ".join(f"{_ws(x['name']) or '(intet navn)'} ({_years(x)})" for x in c["parents"]))
            out.append(f"D {it['source_persona_id']} {it['version']} : _")
        else:
            r += 1
            out.append(f"## FORÆLDREKORT {r}/{n_r} · post {it['record_key']} · PDF-side {it['pages']}")
            out.append(f"#   Hovedperson: {_ws(p['name']) or '(intet navn)'} ({_years(p)})")
            out.append(_clause(it))
            fam = "; ".join(f"{_ws(x['name']) or '(intet navn)'} ({_years(x)})" + (f" · egen post {x['own_post_key']}" if x["own_post_key"] else "")
                            + (" ← modpart" if x["counterpart"] else "") for x in it["partners"])
            out.append(f"#   Familie: {fam}")
            out.append("#   Udsagn: bogen siger, at hovedpersonen er barn af denne familie.")
            out.append(f"R {it['interpretation_key']} {it['version']} : _")
        out.append("")
    return "\n".join(out) + "\n"
```

`parse_sheet`, `check_render` og `check_identity` bevares, bortset fra regex'erne og den nye `ordered`. `decision_sql`:

```python
def decision_sql(lines: list[Line], rows: dict, *, sheet_sha256: str, rows_sha256: str) -> str:
    require_hex64(sheet_sha256, rows_sha256)
    ctl = rows["control_run_id"]
    head = ["BEGIN;", "SET LOCAL ROLE authenticated;",
            "SELECT set_config('request.jwt.claim.sub', :'actor', true) IS NOT NULL AS ok \\g /dev/null",
            "CREATE TEMP TABLE decided(v integer) ON COMMIT DROP;"]
    t1 = ["\\set ON_ERROR_STOP on", *head, f"SELECT red_seal_identity_control_run('{ctl}'::uuid, '{sheet_sha256}', '{rows_sha256}');"]
    t2 = list(head); n1 = n2 = 0
    for l in lines:
        base = {"basis": "human_sheet", "sheet_sha256": sheet_sha256, "rows_sha256": rows_sha256, "line": l.line, "control_run_id": ctl}
        note = sql_literal(f"ark {sheet_sha256[:12]} linje {l.line}" + (f" — {l.note}" if l.note else ""))
        if l.kind == "D":
            pid = f"'{l.item_id}'::uuid, {l.version}"
            if l.tok in "123":
                t1.append(_call("red_afgoer_source_persona", f"{pid}, 'same', NULL, {note}", {**base, "display_position": int(l.tok)}))
            else:
                act = {"X": "different", "N": "new_person_needed", "U": "unresolved"}[l.tok]
                t1.append(_call("red_afgoer_source_persona", f"{pid}, '{act}', NULL, {note}", base))
            n1 += 1
        elif l.tok == "U":
            continue                                   # §23.4: U skriver intet; påstanden forbliver proposed
        else:
            key = f"'{l.item_id}'::uuid, {l.version}"
            if l.tok == "F":
                t2.append(f"INSERT INTO decided SELECT red_classify_parent_card('{ctl}'::uuid, {key}, 'F', {note}, "
                          f"{sql_literal(json.dumps(base, ensure_ascii=False, sort_keys=True))}::jsonb);")
            else:
                act = {"A": "same", "R": "rejected"}[l.tok]
                t2.append(_call("red_afgoer_relation_interpretation", f"{key}, '{act}', NULL, {note}", base))
            n2 += 1
    t1 += [f"DO $$ BEGIN IF (SELECT count(*) FROM decided) <> {n1} THEN RAISE EXCEPTION 'DECISION_COUNT_MISMATCH'; END IF; END $$;",
           f"SELECT red_evaluate_identity_control_run('{ctl}'::uuid) AS kontrolstatus;", "COMMIT;"]
    t2 += [f"DO $$ BEGIN IF (SELECT count(*) FROM decided) <> {n2} THEN RAISE EXCEPTION 'DECISION_COUNT_MISMATCH'; END IF; END $$;",
           "SELECT 'familie_aendret=' || count(*) FROM decided WHERE v=0;", "COMMIT;"]
    return "\n".join(t1 + t2) + "\n"
```
`main()`: `render` skriver ét ark og printer `ARK_OK aegtefaellekort=<n_d> foraeldrekort=<n_r> navnefaeller=<antal stratum navnefaelle>` + `rows_sha256`. Rækkefilen bærer derfor `stratum` pr. identitetskort; det er kun til optælling og renderes ikke. `sql` uden `--part`.

- [ ] **Step 4: Rækkefil v2 (`identity_control_rows.sql`)**

Erstat hele filen:

```sql
-- Trin 5b, spec §23: rækkefil til kontrolarket. Indeholder navne og bogens tekst → 0600 under ~/.private/5b/.
\set ON_ERROR_STOP on
SET default_transaction_read_only=on;
BEGIN;
WITH ctl AS (SELECT * FROM private.identity_control_run WHERE id=:'control_run_id'::uuid),
pv AS (
  SELECT p.id,coalesce(p.visning_fuldt_navn,p.visning_navn) AS name,p.visning_foedt AS born,p.visning_doed AS died,
    coalesce((SELECT jsonb_agg(DISTINCT a.vaerdi_tekst) FROM fact f JOIN conclusion k ON k.target_type='fact' AND k.target_id=f.id
               JOIN assertion a ON a.id=k.valgt_assertion_id WHERE f.subjekt_type='person' AND f.subjekt_id=p.id AND f.faktatype='titel'),'[]'::jsonb) AS titles,
    (SELECT sr.record_key FROM private.source_persona_identity i
       JOIN private.source_persona_mention spm ON spm.persona_id=i.source_persona_id AND spm.mention_role='primary'
       JOIN private.source_mention sm ON sm.id=spm.mention_id
       JOIN private.source_observation o ON o.id=sm.observation_id AND o.parent_observation_id IS NULL
       JOIN private.source_record_anchor_current ac ON ac.occurrence_id=o.occurrence_id AND ac.decision_status='accepted'
       JOIN private.source_record sr ON sr.id=ac.source_record_id
      WHERE i.canonical_person_id=p.id AND i.decision_status='accepted' ORDER BY sr.record_key LIMIT 1) AS own_post_key,
    coalesce((SELECT jsonb_agg(jsonb_build_object('name',coalesce(pp.visning_fuldt_navn,pp.visning_navn),'born',pp.visning_foedt,
               'died',pp.visning_doed) ORDER BY pp.id)
       FROM family_member fb JOIN family_member fp ON fp.family_id=fb.family_id AND fp.rolle='partner'
       JOIN person pp ON pp.id=fp.person_id WHERE fb.person_id=p.id AND fb.rolle='barn'),'[]'::jsonb) AS parents
    FROM person p),
clause AS (  -- påstandens støttende observation (ordinal 1) og dens post
  SELECT ic.interpretation_key,o.id AS observation_id,o.verbatim_text AS text,o.page_from,o.page_to,o.char_from,sr.record_key
    FROM private.interpretation_current ic
    JOIN private.interpretation_observation io ON io.interpretation_id=ic.id AND io.ordinal=1
    JOIN private.source_observation o ON o.id=io.observation_id
    JOIN private.source_record_anchor_current ac ON ac.occurrence_id=o.occurrence_id AND ac.decision_status='accepted'
    JOIN private.source_record sr ON sr.id=ac.source_record_id),
idc AS (
  SELECT s.*,pc.interpretation_key,pc.marriage_ordinal,cl.observation_id,cl.text,cl.page_from,cl.page_to,cl.record_key,
         (SELECT jsonb_build_array(sm.char_from-cl.char_from,sm.char_to-cl.char_from)
            FROM private.source_persona_mention spm JOIN private.source_mention sm ON sm.id=spm.mention_id
           WHERE spm.persona_id=s.source_persona_id AND spm.mention_role='spouse' AND sm.observation_id=cl.observation_id) AS span,
         private.spouse_principal_person(s.source_persona_id) AS hp
    FROM private.identity_control_sample s
    JOIN private.interpretation_party_current pc ON pc.source_persona_id=s.source_persona_id AND pc.party_role='spouse'
    JOIN clause cl ON cl.interpretation_key=pc.interpretation_key
   WHERE s.control_run_id=(SELECT id FROM ctl) AND s.sample_kind='identity'),
prc AS (
  SELECT pcard.*,cl.observation_id,cl.text,cl.page_from,cl.page_to,cl.record_key,
         (SELECT i.canonical_person_id FROM private.interpretation_party_current pr
            JOIN private.source_persona_identity i ON i.source_persona_id=pr.source_persona_id AND i.decision_status='accepted'
           WHERE pr.interpretation_key=pcard.interpretation_key AND pr.party_role='principal') AS hp
    FROM private.identity_control_parent_card pcard JOIN clause cl ON cl.interpretation_key=pcard.interpretation_key
   WHERE pcard.control_run_id=(SELECT id FROM ctl))
SELECT jsonb_build_object('control_run_id',(SELECT id FROM ctl),'candidate_run_id',(SELECT candidate_run_id FROM ctl),
  'k_random',(SELECT k_random FROM ctl),'items',coalesce((SELECT jsonb_agg(item) FROM (
    SELECT jsonb_build_object('kind','identity','stratum',x.stratum,'source_persona_id',x.source_persona_id,'version',x.identity_version,
      'record_key',x.record_key,'pages',CASE WHEN x.page_from=x.page_to THEN x.page_from::text ELSE x.page_from||'–'||x.page_to END,
      'principal',(SELECT jsonb_build_object('name',name,'born',born,'died',died) FROM pv WHERE pv.id=x.hp),
      'marriage_ordinal',x.marriage_ordinal,'observation_id',x.observation_id,
      'text_sha256',encode(extensions.digest(convert_to(x.text,'UTF8'),'sha256'),'hex'),'text',x.text,'span',x.span,
      'display',(SELECT jsonb_agg(jsonb_build_object('position',m.key::int,'candidate_id',c.id,'name',pv.name,'born',pv.born,'died',pv.died,
                  'titles',pv.titles,'own_post_key',pv.own_post_key,'parents',pv.parents) ORDER BY m.key::int)
                 FROM jsonb_each_text(x.mapping) m JOIN private.source_persona_identity_candidate c ON c.id=m.value::uuid
                 JOIN pv ON pv.id=c.candidate_person_id)) AS item
      FROM idc x
    UNION ALL
    SELECT jsonb_build_object('kind','parent','interpretation_key',y.interpretation_key,'version',y.interpretation_version,
      'record_key',y.record_key,'pages',CASE WHEN y.page_from=y.page_to THEN y.page_from::text ELSE y.page_from||'–'||y.page_to END,
      'principal',(SELECT jsonb_build_object('name',name,'born',born,'died',died) FROM pv WHERE pv.id=y.hp),
      'observation_id',y.observation_id,'text_sha256',encode(extensions.digest(convert_to(y.text,'UTF8'),'sha256'),'hex'),'text',y.text,
      'family_id',y.family_id,
      'partners',(SELECT jsonb_agg(jsonb_build_object('name',pv.name,'born',pv.born,'died',pv.died,'own_post_key',pv.own_post_key,
                    'counterpart',pv.id=y.counterpart_person_id) ORDER BY pv.id) FROM pv WHERE pv.id=ANY(y.partner_ids)))
      FROM prc y) items),'[]'::jsonb));
COMMIT;
```
Kolonnenavnene `source_mention.char_from/char_to` og `source_observation.char_from` verificeres mod `schema.sql` før kørsel (Opus-review: mentionens offsets ligger på klausulobservationen). Afviger de, ledges en `Ruling:` med den faktiske beregning. `test_clause_readers`: filen nævner hverken `observation_kind='clause'`, `parent_observation_id … clause` eller `clause_ordinal` som filter ud over den eksisterende ALLOWED-begrundelse. Behold den eksisterende ALLOWED-linje og opdatér begrundelsen, hvis vagten kræver det.

- [ ] **Step 5: Kør testene og se dem bestå**

Run: `env -u NODE_OPTIONS /usr/bin/python3 -m pytest -q .claude/skills/daa-extract/scripts/test_identity_control_sheet.py .claude/skills/daa-extract/scripts/test_clause_readers.py`
Expected: alle PASS.

- [ ] **Step 6: Røgtest af rækkefilen mod en testbase (kun tal)**

På en frisk `ci5b_v2` (Task 12's opsætning), kør `tests/sql/test-identity-control-run.sql`'s `$control_v2$`-verden uden ROLLBACK. Brug en kopi af blokken i `$SP/v2-world.sql`, der slutter med `COMMIT` og printer `ctl=<id>`. Derefter:

```bash
PGDATABASE=ci5b_v2 psql -X -At -q -v actor=11000000-0000-0000-0000-00000005b701 -v control_run_id=<ctl> \
  -f .claude/skills/daa-extract/scripts/identity_control_rows.sql > $SP/v2-rows.json
/usr/bin/python3 .claude/skills/daa-extract/scripts/identity_control_sheet.py render --rows $SP/v2-rows.json --out $SP/v2-ark.txt
```
Expected: `ARK_OK aegtefaellekort=3 foraeldrekort=0 navnefaeller=1`. (Testverdenens navne er syntetiske, så arket må læses.) Drop `ci5b_v2`.

- [ ] **Step 7: Hele python-jobbet og commit**

```bash
git add .claude/skills/daa-extract/scripts/identity_control_rows.sql .claude/skills/daa-extract/scripts/identity_control_sheet.py .claude/skills/daa-extract/scripts/test_identity_control_sheet.py
/usr/bin/python3 $SP/localci.py python 55435 | grep -v "rc=0"
git commit -m "feat(151): kontrolark v2 — kort med hovedperson, bogens sætning og forældre (spec §23)

Claude-Session: https://claude.ai/code/session_018KPNPJmdDmYBKcQQ14VfHb"
```
Expected: `python FAILS=0`.

---

### Task 14: Del 1's færdigbevis (erstatter hovedplanens Task 10 fra Step 4)

**Files:** ingen kode. Tal i ledgeren.

**Interfaces:** Task 11's kandidatkørsel (top-k 10) i bevisbasen; Task 12-13.

- [ ] **Step 1: Løft bevisbasen**

```bash
DB=$(cat $SP/bevis2-db.txt)
for f in db-migrations.sql db-rls.sql; do psql -X -q -v ON_ERROR_STOP=1 -d $DB -f $f >/dev/null 2>$SP/b3-mig.err || { echo FAIL $f; tail -3 $SP/b3-mig.err | sed -E 's/[0-9a-f-]{8,}/<hex>/g'; }; done
psql -X -q -v ON_ERROR_STOP=1 -d $DB -f tests/sql/run-db-verify-disposable.sql >/dev/null 2>$SP/b3-ver.err && echo VERIFY_OK
```
Expected: `VERIFY_OK`. Migrationerne ændrer ikke kandidatinputtet. Ændrer de det alligevel, giver Step 2 `IDENTITY_CONTROL_INPUT_DRIFT`. Så køres Task 11 Step 1 igen (ny eksport + generate + write), og der ledges en `Ruling:`.

- [ ] **Step 2: Registrér, rækkefil og ark**

```bash
psql -X -At -q -d $DB -v actor="$A" -v run="$(cat $SP/bevis2-run-k10.txt)" -f $SP/register-ctl.sql 2>$SP/b3-reg.err | grep '^ctl=' | cut -c5- > $SP/bevis3-ctl.txt
[ -s $SP/bevis3-ctl.txt ] || sed -E 's/[0-9a-f-]{8,}/<hex>/g' $SP/b3-reg.err | tail -3
psql -X -At -q -d $DB -v actor="$A" -v control_run_id="$(cat $SP/bevis3-ctl.txt)" -f .claude/skills/daa-extract/scripts/identity_control_rows.sql > $P/kontrol-rows.json 2>$P/kontrol-rows.err
/usr/bin/python3 .claude/skills/daa-extract/scripts/identity_control_sheet.py render --rows $P/kontrol-rows.json --out $P/KONTROL.txt
psql -X -At -d $DB -c "select stratum,count(*) from private.identity_control_sample where control_run_id='$(cat $SP/bevis3-ctl.txt)' group by 1 order by 1;
  select reason,count(*) from private.identity_control_exclusion where control_run_id='$(cat $SP/bevis3-ctl.txt)' group by 1 order by 1;
  select 'forældrekort',count(*) from private.identity_control_parent_card where control_run_id='$(cat $SP/bevis3-ctl.txt)'"
```
Expected: `ARK_OK aegtefaellekort=… foraeldrekort=… navnefaeller=…` (forventet ca. 31 / 9 / 11, jf. Task 11), `rows_sha256 …`, strata-tal og udelukkelser. Ledger tallene. Projektejeren udfylder `~/.private/5b/KONTROL.txt` og giver hashen (`! shasum -a 256 ~/.private/5b/KONTROL.txt`). **Stop her og vent på hashen.**

> **Tillæg 2026-10-10 (under udfyldningen):** projektejeren fandt et kort, hvor to kandidater er samme
> individ (dublet i basen). Spec §23.4 har fået dublet-svaret `1=2`. Arket gengives med ny forklaringslinje,
> og de allerede skrevne svar overføres pr. id til den nye gengivelse (`$SP/overfoer-svar.py`). Rækkefilen er
> uændret, så `rows_sha256` er den samme. Projektejeren tager hash af det **nye** ark.
> Samme dag: forældrekortene markerer forældreudsagnet `[[…]]` og stiller udsagnet som spørgsmål. Det ændrer
> rækkefilen (felt `span` på forældrekort) ⇒ ny rækkefil `kontrol-rows-v3.json` og nyt `rows_sha256`;
> overførslen bruger den nye rækkefil.

- [ ] **Step 3: Negativtests i en kopi**

`createdb -T $DB daa5b_neg_$TS`. I kopien:
1. `red_corroborate_family_identities` før forsegling ⇒ `IDENTITY_CONTROL_NOT_PASSED`.
2. Arkets SQL med én ægtefællelinje ændret til `U` (kopi af arket, ny hash) ⇒ `kontrolstatus = failed`, bekræftelsen bagefter = 0.
3. Forkert mængde-hash ⇒ `IDENTITY_CORROBORATION_SET_DRIFT`, 0 nye hændelser.
4. En udelukket persona: direkte kernekald med kontrolkørslens id ⇒ `FAMILY_CORROBORATION_CONTROL_NOT_PASSED`.
5. Et forældrekort `A` efter en tilføjet familie ⇒ `familie_aendret=1`, og kontrolstatus er uændret.

Omdøb kopien til `slet_<MMDD>__daa5b_neg_$TS` efter at have målt størrelsen. Ledger udfaldene.

- [ ] **Step 4: Den rigtige kørsel**

```bash
/usr/bin/python3 .claude/skills/daa-extract/scripts/identity_control_sheet.py sql --sheet $P/KONTROL.txt --approved-sha256 <hash> \
  --rows $P/kontrol-rows.json --expect-rows-sha256 <rows_sha256> --out $P/kontrol.sql
psql -X -At -q -d $DB -v actor="$A" -f $P/kontrol.sql 2>&1 | grep -v -- "$A" | sed -E 's/[0-9a-f-]{8,}/<hex>/g'
```
Expected: `passed` (eller `failed` ⇒ stop, afvigelserne gennemgås med projektejeren efter §23.4 »Efter `failed`«), derefter `familie_aendret=0`. Ved `passed`: beregn mængde-hashen over egnede rang-1-personas i kørslen, der er uafgjorte, ikke i stikprøven og ikke udelukkede (som `corr_set`), og kør `red_corroborate_family_identities(<ctl>, '<hash>')`. Ledger:
- antal ægtefællekort pr. stratum og antal afvigelser;
- grænsen `1 − 0,05^(1/K)` for K = antal tilfældige kort;
- antal udelukkede pr. grund og antal maskinelt bekræftede;
- forældrenes A/R/F/U.

- [ ] **Step 5: Webspor-paritet (hovedplanens Task 10 Step 7)**

Uændret: én uoverensstemmelses-persona afgøres via psql med webkøens payload (`basis: web_detail`, `candidate_id`, `run_id`); evidensnøglerne sammenlignes med en arklinjes. Kun nøgler i ledgeren.

- [ ] **Step 6: Ledger-afslutning**

`Task 10: complete (del 1-bevis v3: base …, N personas, E egnede, U udelukket, S ægtefællekort [navnefæller n, tilfældige K], afvigelser a, grænse g %, M maskinelt, forældre A/R/F/U, status passed)`. Bevisbasen bevares til del 2. Ingen commit.

---

## Selvreview

- **Spec-dækning:**
  - §23.2(a) → Task 13 render + rækkefil (hovedperson, side, klausul med `[[…]]`, kandidater med titler, egen post og forældre; ingen score).
  - §23.2(b) → Task 13 (familie, modpart, udsagn; A/R/F/U).
  - §23.3 pkt. 1–5 → Task 12 Step 4–5 (`person_life_bounds`, `candidate_impossible`, udelukkelse, navnefæller over `visning_navn`/`visning_fuldt_navn`, `control_allocate`, visning ≤ 3, grænse 40).
  - Top-k 10 → Task 11.
  - Forældrekort-lagring → Task 12 Step 4–5.
  - §23.4: to forløb → Step 6–7 + Task 13's to transaktioner; tokens → Step 7; grænse → Task 14 Step 4; efter `failed` → Task 14 Step 4; tekstbinding → rækkefilens `text_sha256` (append-only).
  - §23.5 → intet i del 1 (bevidst).
  - §23.6 → Task 14.
  - §22.9 → allerede committet (719ef4f).
- **Typer på tværs:**
  - Task 13's rækkefil læser `identity_control_parent_card.partner_ids` og `counterpart_person_id` fra Task 12.
  - `red_classify_parent_card` har seks argumenter i både Task 12 og Task 13's SQL. Rækkefølgen er `ctl, key, version, 'F', note, ctx` — Task 13's kald passer.
  - `red_afgoer_relation_interpretation` kaldes med `NULL` som familie på kortvejen.
- **Review Focus:** punkt 1, 4 og 5 → Task 12 Step 1; punkt 2 → Task 13 Step 1; punkt 3 → Task 12 Step 2 og Task 13 Step 1.
- **Kendte usikkerheder (rettes under udførelsen med ledgeret ruling):**
  - kolonne-NOT NULL-krav i `fact`/`assertion`/`conclusion` til testhjælperen;
  - mention-offsets;
  - `control_allocate`-forventningen, som allerede er rettet i Step 1-teksten.
