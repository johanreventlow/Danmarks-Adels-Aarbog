# #244 — ægteskabsnummeret efter skriverens vindue: implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `private.relation_marriage_ordinals` placerer ægteskabspåstande med skriverens vindue. Et værn stopper modsigelser mod bogens »g. N°«. De 4 skævt gemte ægteskabsnumre i 2018-20 rettes på et lille hash-bundet ark og genbindes i samme familie.

**Architecture:** Arbejdet har fem dele:
- **Rodrettelse:** én SQL-ændring. `relation_ordered_windows` flyttes op i `schema.sql`, så den findes, når SQL-funktionen oprettes.
- **Bognummeret:** én SQL-funktion (`private.relation_book_ordinal`) med en Python-tvilling (`book_ordinal`) og en fælles paritetsliste.
- **Rettelsesskriveren** (`public.red_ret_aegteskabsnummer`) skriver en ny ægtefællepartversion og en række i en ny tilføj-kun-tabel. Den rører ikke fortolkningen.
- **Arket** genbruger børnearkets mekanik (`decision_sheet_core`, `_write_private`, `check_private_path`).
- **Genbindingen** bruger den eksisterende 2b-i-vej uændret.

**Tech Stack:** PostgreSQL 17 (plpgsql/sql), Python 3 (ark og pytest), bash-e2e.

**Spec:** `docs/superpowers/specs/2026-10-20-244-aegteskabsnumre-design.md` (GODKENDT 2026-10-20). 2b-i-specen §4.2 og 2b-iii-specen §6 er baggrund.

## Global Constraints

- **Kun restore.** Ingen prod-mutation, intet push uden et udtrykkeligt ja, og PR'er altid `--draft`.
- **`schema.sql` er source of truth.** `db-migrations.sql` får idempotente kopier i én #244-blok over linjen `-- 5b-sektionen slutter her (nye 5b-blokke indsættes over denne linje).`
- **Nye public-funktioner** kommer i alle tre lister:
  - `db-rls.sql` (grant-listen ved `'public.red_relation_child_sheet_input(bigint)'`);
  - `db-verify.sql` (`::regprocedure`-listen ved samme navn);
  - `db-migrations.sql` (`to_regprocedure`-listen ved samme navn).
- **Fejlkoder:**
  - `MARRIAGE_ORDINAL_CORRECTION_CONTEXT_INVALID|NOT_BOUND|VERSION_MISMATCH|NOT_NEEDED|FAMILY_MISMATCH|BOOK_MISMATCH|STATE_INVALID`;
  - `REIMPORT_WRITER_RELATION_PERSONA_ORDINAL_BOOK_MISMATCH`;
  - `SHEET_TOKEN_NOT_ALLOWED`, `SHEET_LINE_UNKNOWN`, `SHEET_LINE_DUPLICATE`, `SHEET_LINES_MISSING`, `SHEET_HASH_MISMATCH`, `ROWS_CONTRACT_INVALID`.
- **Bognummer-mønstret** sammenlignes efter `lower()`: `^[ \t]*(g[.]|gift)[ \t]*([0-9]{1,3})[ \t]*[°º]` (`[.]` i stedet for `\.`, så en sql-krop ikke afhænger af `standard_conforming_strings` ved kaldet). Det bruger ingen `\s`, `\d` eller `\w`, og loftet på 3 cifre forhindrer overløb i en integer.
- **PII.** Navne og bogens tekst må kun forekomme i `~/.private/244/` (0700/0600). Rapporter, commits og chat indeholder kun tal og hashes. Tests bruger opdigtede navne.
- **Commits** er atomiske danske Conventional Commits med trailer `Claude-Session: https://claude.ai/code/session_011rKEYw62xDPse4zhLARtjo` og uden Claude-attribution.
- **Miljø:** `env -u PGOPTIONS` foran psql og `env -u NODE_OPTIONS` foran npm.
- **Testbase:** SQL-testene kører i `writer_1939`, bygget som i CI (`.superpowers/sdd/<plan>/ci/run_all.sh` fra 2b-iii kan genbruges som skabelon).

## Review Focus

1. **NULL-`raw` eller en tekst uden vindue i en post med flere ægteskaber.** Positionen skal blive NULL og sorteres sidst, ikke fejle. Det låses af `ordinals_uden_vindue` i Task 1.
2. **Samtidig afvisning af en søskendepåstand i samme post, mens rettelsen kører.** Rettelsen skal vente på låsen eller fejle lukket. Det låses af dblink-testen `ret_venter_paa_soeskende` i Task 3.
3. **Bognummer med `º` (ordinal-tegn) i stedet for `°`, versaler, eller et tal i en parentes.** Python og SQL skal give samme svar. Det låses af paritetslisten i Task 2.
4. **Et ark, hvor en linje er rettet efter godkendelsen, eller hvor samme linje anvendes to gange.** Det skal give `SHEET_HASH_MISMATCH` og `…_VERSION_MISMATCH`. Det låses i Task 4 (e2e) og Task 3 (gentaget kald).
5. **Familienummer NULL eller forskelligt fra det nye nummer.** Rettelsen må ikke skrive. Det låses af `ret_familie_null` og `ret_familie_forkert` i Task 3.

---

### Task 1: Rodrettelsen — `relation_marriage_ordinals` bruger vinduet

**Files:**
- Modify: `schema.sql`:
  - Flyt hele blokken for `private.relation_ordered_windows` op, så den står umiddelbart før kommentaren `-- Trin 5b (#151): serverens ægteskabsnummer.` (~14899). Blokken er kommentarlinjerne fra `-- ===…` med »Ord = løb af den eksplicitte klasse« ned til `REVOKE ALL ON FUNCTION private.relation_ordered_windows(text,text) …` (~17060–17096).
  - Erstat derefter kroppen i `relation_marriage_ordinals`.
- Modify: `db-migrations.sql`: ny blok `-- #244 (spec 2026-10-20): …` over `-- 5b-sektionen slutter her`.
- Create: `tests/sql/fixtures/marriage-ordinal-244.sql`.
- Create: `tests/sql/test-marriage-ordinal-correction.sql` (del 1. Task 2 og 3 udvider filen).
- Modify: `.github/workflows/ci.yml`: tilføj `test-marriage-ordinal-correction` sidst i løkken `for t in test-relation-persona-v2 … test-relation-child; do`.

**Interfaces:**
- Produces:
  - `private.relation_marriage_ordinals(uuid)` med uændret signatur og ny position;
  - fixture-helperen `pg_temp.f244_post(p_source bigint,p_src jsonb,p_key text,p_principal bigint,p_s1 bigint,p_s2 bigint,p_actor uuid) RETURNS jsonb` med nøglerne `post, c1, c2, s1, s2, f1, f2`.

**Fixturens data:** påstand `c1` springer en parentes over, og ægtefællepartens gemte nummer er det gamle fejlnummer (c1 → 2, c2 → 1). Familierne har de rigtige numre (f1 = 1, f2 = 2).

- [ ] **Step 1: Skriv fixturen** `tests/sql/fixtures/marriage-ordinal-244.sql`:

```sql
-- #244: fixtures oven på relation-5b.sql og relation-2a.sql. Kaldes som ejer. Opdigtede navne.
-- En post med to ægteskaber. Påstand 1 springer en parentes over (som de 6 i 2018-20) og står derfor ikke ordret
-- i klausulen. Ægtefællepartens nummer gemmes som den gamle funktion gav det (1↔2 byttet); familierne er rigtige.
-- p_k1/p_raw1 styrer påstand 1 (ret_bog bruger »Gift 2° …« i begge, så vinduet findes, og bogen siger 2).
-- p_third: en tredje ægteskabspåstand (uden familie, forbliver proposed) til låsetesten.
-- Posten publiceres (kontrakt 2), så public_family_sources kan vise kilderne (test-family-sources.sql:14).
CREATE OR REPLACE FUNCTION pg_temp.f244_post(p_source bigint,p_src jsonb,p_key text,p_principal bigint,p_s1 bigint,p_s2 bigint,
  p_actor uuid,p_k1 text DEFAULT 'Gift 1° m. Bo Beta (søn af Ole Oma) f. 1800.',p_raw1 text DEFAULT 'Gift 1° m. Bo Beta f. 1800.',
  p_third boolean DEFAULT false) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE p jsonb; c1 jsonb; c2 jsonb; c3 jsonb; v1 uuid; v2 uuid; f1 bigint; f2 bigint; v_at timestamptz:=clock_timestamp();
  v_k2 text:='Gift 2° m. Cia Ceta.'; v_k3 text:='Gift 3° m. Dy Delta.'; v_text text; v_clauses text[];
BEGIN
  v_text:='Anna Alfa. '||p_k1||' '||v_k2||CASE WHEN p_third THEN ' '||v_k3 ELSE '' END;
  v_clauses:=ARRAY['Anna Alfa.',p_k1,v_k2]||CASE WHEN p_third THEN ARRAY[v_k3] ELSE '{}'::text[] END;
  p:=pg_temp.f5b_post(p_source,p_src,p_key,v_text,v_clauses,p_principal,p_actor);
  PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
  PERFORM pg_temp.f2a_publish(p_source,p_src,p,p_principal,p_actor,v_text);
  c1:=pg_temp.f5b_claim(p_source,p_src,'relation.marriage',(p->'clauses'->>1)::uuid,p_raw1);
  c2:=pg_temp.f5b_claim(p_source,p_src,'relation.marriage',(p->'clauses'->>2)::uuid,v_k2);
  IF p_third THEN c3:=pg_temp.f5b_claim(p_source,p_src,'relation.marriage',(p->'clauses'->>3)::uuid,v_k3); END IF;
  v1:=pg_temp.f5b_spouse(p_source,p_src,p,c1,(p->'clauses'->>1)::uuid,'Bo Beta',2);
  v2:=pg_temp.f5b_spouse(p_source,p_src,p,c2,(p->'clauses'->>2)::uuid,'Cia Ceta',1);
  INSERT INTO private.source_persona_identity_event(source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at)
    VALUES (v1,p_s1,'accepted',1,'{"fixture":"244"}',p_actor,'fixture',v_at),(v2,p_s2,'accepted',1,'{"fixture":"244"}',p_actor,'fixture',v_at);
  INSERT INTO private.source_persona_identity(source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at)
    VALUES (v1,p_s1,'accepted',1,'{"fixture":"244"}',p_actor,'fixture',v_at),(v2,p_s2,'accepted',1,'{"fixture":"244"}',p_actor,'fixture',v_at);
  f1:=pg_temp.f5b_family(p_principal,p_s1,1);
  f2:=pg_temp.f5b_family(p_principal,p_s2,2);
  RETURN jsonb_build_object('post',p,'c1',c1,'c2',c2,'c3',c3,'s1',v1,'s2',v2,'f1',f1,'f2',f2);
END $$;

-- Afgør kildens ægteskaber maskinelt (2a) og bind alle egnede (2b-i-vejen) som aktøren. Returnerer antal bindinger.
CREATE OR REPLACE FUNCTION pg_temp.f244_decide_and_bind(p_source bigint,p_actor uuid) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE pv jsonb; v_items jsonb; v_prev jsonb; n int;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_decisions(p_source);
  PERFORM red_decide_relation_interpretations(p_source,pv->>'set_sha256');
  RESET ROLE;
  RETURN pg_temp.f244_bind(p_source,p_actor);
END $$;

CREATE OR REPLACE FUNCTION pg_temp.f244_bind(p_source bigint,p_actor uuid) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE v_all jsonb; v_pv jsonb; v_items jsonb;
BEGIN
  SELECT coalesce(jsonb_agg(jsonb_build_object('interpretation_id',ic.id::text,
           'family_id',(private.relation_binding_state(ic.id)#>>'{family,family_id}')::bigint) ORDER BY ic.id::text COLLATE "C"),'[]')
    INTO v_all FROM private.interpretation_current ic
   WHERE ic.source_id=p_source AND ic.status='accepted' AND private.relation_binding_state(ic.id) IS NOT NULL;
  IF jsonb_array_length(v_all)=0 THEN RETURN 0; END IF;   -- tom liste giver RELATION_PROMOTION_ITEMS_INVALID
  PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
  SET LOCAL ROLE authenticated;
  v_pv:=red_preview_relation_promotions(p_source,v_all);
  SELECT coalesce(jsonb_agg(jsonb_build_object('interpretation_id',i->>'interpretation_id','family_id',(i->>'family_id')::bigint)
           ORDER BY i->>'interpretation_id' COLLATE "C"),'[]')
    INTO v_items FROM jsonb_array_elements(v_pv->'items') i WHERE (i->>'eligible')::boolean;
  IF jsonb_array_length(v_items)=0 THEN RESET ROLE; RETURN 0; END IF;
  v_pv:=red_preview_relation_promotions(p_source,v_items);
  PERFORM red_promote_relation_interpretations_batch(p_source,v_items,v_pv->>'preview_sha256');
  RESET ROLE;
  RETURN jsonb_array_length(v_items);
END $$;
```

- [ ] **Step 2: Skriv den fejlende test** (opret `tests/sql/test-marriage-ordinal-correction.sql`):

```sql
-- #244 (spec 2026-10-20): ægteskabsnummer efter vinduet, bognummer, værn, rettelsesskriver og genbinding.
-- Opdigtede navne. Kører i writer_1939 som ejer.
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
\ir fixtures/marriage-ordinal-244.sql
DO $ordinals_vindue$
DECLARE v_actor uuid:='11000000-0000-0000-0000-000000024401'; s jsonb; m jsonb; c jsonb; p jsonb; v_ord int[];
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) SELECT g,false,false,'244' FROM generate_series(-24409,-24401) g;
  s:=pg_temp.f5b_source(-24401);
  m:=pg_temp.f244_post(-24401,s,'O-1',-24401,-24402,-24403,v_actor);
  -- ordinals_parentes: påstand 1 (springer parentesen over) er nr. 1, påstand 2 er nr. 2
  SELECT array_agg(o.marriage_ordinal ORDER BY o.interpretation_key=(m->'c1'->>'key')::uuid DESC) INTO v_ord
    FROM private.relation_marriage_ordinals((m->'post'->>'occ')::uuid) o;
  IF v_ord IS DISTINCT FROM ARRAY[1,2] THEN RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: parentes %',v_ord; END IF;
  IF (SELECT o.post_offset FROM private.relation_marriage_ordinals((m->'post'->>'occ')::uuid) o
       WHERE o.interpretation_key=(m->'c1'->>'key')::uuid) IS DISTINCT FROM
     (SELECT post_char_from FROM private.source_observation WHERE id=(m->'post'->'clauses'->>1)::uuid) THEN
    RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: position';
  END IF;
  -- ordinals_uden_vindue: en påstand uden ordvindue i en post med to ægteskaber → NULL, sorteret sidst
  p:=pg_temp.f5b_post(-24401,s,'O-2','Eva Epsilon. Gift 1° m. Ib Iota. Gift 2° m. Jo Jota.',
       ARRAY['Eva Epsilon.','Gift 1° m. Ib Iota.','Gift 2° m. Jo Jota.'],-24404,v_actor);
  c:=pg_temp.f5b_claim(-24401,s,'relation.marriage',(p->'clauses'->>1)::uuid,'Gift m. Xu Xa.');
  PERFORM pg_temp.f5b_claim(-24401,s,'relation.marriage',(p->'clauses'->>2)::uuid,'Gift 2° m. Jo Jota.');
  IF (SELECT array_agg(o.post_offset IS NULL ORDER BY o.marriage_ordinal) FROM private.relation_marriage_ordinals((p->>'occ')::uuid) o)
     IS DISTINCT FROM ARRAY[false,true] THEN
    RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: uden vindue';
  END IF;
  -- ordinals_null_raw: NULL-raw giver NULL-position (STRICT), ikke fejl. interpretation er tilføj-kun, så en ny post.
  p:=pg_temp.f5b_post(-24401,s,'O-3','Fie Fi. Gift m. Gro Gamma.',ARRAY['Fie Fi.','Gift m. Gro Gamma.'],-24405,v_actor);
  PERFORM pg_temp.f5b_claim(-24401,s,'relation.marriage',(p->'clauses'->>1)::uuid,NULL);
  IF (SELECT o.post_offset FROM private.relation_marriage_ordinals((p->>'occ')::uuid) o) IS NOT NULL THEN
    RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: NULL-raw';
  END IF;
  RAISE NOTICE 'OK: ægteskabsnummer efter vinduet';
END $ordinals_vindue$;
ROLLBACK;
```

> **Transaktionsramme.** Hver DO-blok i denne fil står i sin egen `BEGIN; \ir fixtures/relation-5b.sql; \ir fixtures/relation-2a.sql; \ir fixtures/marriage-ordinal-244.sql; DO …; ROLLBACK;`. Ellers committes fixturrækker automatisk i `writer_1939`. Det gælder også blokkene i Task 2 og 3.

- [ ] **Step 3: Kør testen og se den fejle.** Byg `writer_1939` som i CI, kør `env -u PGOPTIONS psql -X -d writer_1939 -v ON_ERROR_STOP=1 -f tests/sql/test-marriage-ordinal-correction.sql`.
  Expected: `ORDINAL_244_TEST_FAILED: parentes {2,1}`.

- [ ] **Step 4: Implementér.** I `schema.sql`: flyt vindue-blokken (se Files), og udskift `relation_marriage_ordinals`:

```sql
-- Trin 5b (#151): serverens ægteskabsnummer. Rang efter (post_offset, spændlængde,
-- interpretation_key) over ALLE ikke-afviste ægteskabspåstande i posten — også dem,
-- udtrækket parkerer — så numrene ikke flytter sig mellem kørsler (spec §5.1).
-- #244: positionen er starten af det eneste minimale ordnede ordvindue (som skriverens spændtjek), ikke strpos:
-- en påstand, der springer en parentes over, står ikke ordret i klausulen. Uden præcis ét vindue: NULL (sidst).
CREATE OR REPLACE FUNCTION private.relation_marriage_ordinals(p_occurrence uuid)
RETURNS TABLE(interpretation_key uuid, marriage_ordinal integer, post_offset integer)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,private AS $$
  WITH m AS (
    SELECT ic.interpretation_key, ic.value->>'raw' AS raw,
           co.post_char_from+(SELECT CASE WHEN count(*)=1 THEN min(w.w_from) END
                                FROM private.relation_ordered_windows(co.verbatim_text,ic.value->>'raw') w) AS post_offset
      FROM private.interpretation_current ic
      JOIN private.interpretation_observation io ON io.interpretation_id=ic.id AND io.evidence_role='supporting' AND io.ordinal=1
      JOIN private.clause_observation_current co ON co.id=io.observation_id
     WHERE ic.predicate='relation.marriage' AND ic.status<>'rejected' AND co.occurrence_id=p_occurrence)
  SELECT m.interpretation_key,
         (row_number() OVER (ORDER BY m.post_offset NULLS LAST,char_length(m.raw),m.interpretation_key::text COLLATE "C"))::integer,
         m.post_offset
    FROM m;
$$;
REVOKE ALL ON FUNCTION private.relation_marriage_ordinals(uuid) FROM PUBLIC,anon,authenticated;
```

  I `db-migrations.sql`: åbn #244-blokken over `-- 5b-sektionen slutter her` med kommentaren `-- #244 (spec 2026-10-20-244-aegteskabsnumre-design): …`, og indsæt samme `CREATE OR REPLACE` plus `REVOKE`. Funktionen `relation_ordered_windows` er allerede defineret tidligere i migrationerne.

- [ ] **Step 5: Kør testen og den eksisterende writer-test.**
  Run: test-filen, og `test-relation-persona-writer.sql`, `test-family-corroboration.sql`, `test-relation-persona-v2.sql` og `test-relation-persona-v3.sql`.
  Expected: `OK: ægteskabsnummer efter vinduet`, og alle eksisterende er grønne.

- [ ] **Step 6: Frisk opbygning.** Run: `createdb t244_fresh` og indlæs `tests/sql/evidence-promotion-bootstrap.sql schema.sql db-rls.sql` med `ON_ERROR_STOP`.
  Expected: ingen »function … does not exist«.

- [ ] **Step 7: Commit:** `fix(244): ægteskabsnummeret placeres med skriverens ordvindue`. Filer: schema.sql, db-migrations.sql, fixturen, test-filen og ci.yml.

---

### Task 2: Bognummeret og værnet

**Files:**
- Modify: `schema.sql`. Ny `private.relation_book_ordinal` lige efter `relation_marriage_ordinals`. Tilføj værnet i `private.write_relation_persona` lige efter blokken `IF v_ordinal IS DISTINCT FROM (p_payload->>'marriage_ordinal')::integer … SPAN_INVALID … END IF;` (~15088–15092).
- Modify: `db-migrations.sql` (#244-blokken):
  - `CREATE OR REPLACE` af `relation_book_ordinal`;
  - **hele** `write_relation_persona` kopieret fra den **seneste** definition i filen (i dag ~23203) plus værnet, med samme REVOKE/GRANT-linjer som den kopierede.
- Create: `tests/fixtures/relation-book-ordinal.json`.
- Modify: `.claude/skills/daa-extract/scripts/relation_persona_extract_v3.py` og `test_relation_persona_extract_v3.py`.
- Modify: `tests/sql/test-marriage-ordinal-correction.sql` (ny DO-blok).

**Interfaces:**
- Produces:
  - `private.relation_book_ordinal(p_raw text) RETURNS integer` (IMMUTABLE STRICT);
  - `relation_persona_extract_v3.book_ordinal(raw: str | None) -> int | None`;
  - U-grunden `nummer_modsiger_bog`.

- [ ] **Step 1: Paritetslisten** `tests/fixtures/relation-book-ordinal.json`:

```json
[
  {"raw": "g. 1° m. Anna Alfa", "expect": 1},
  {"raw": "Gift 2° m. Bo Beta", "expect": 2},
  {"raw": "GIFT 3º m. Cia Ceta", "expect": 3},
  {"raw": "  g.  12 ° m. Dan Delta", "expect": 12},
  {"raw": "g.1°m. Eva Epsilon", "expect": 1},
  {"raw": "\tgift\t4°", "expect": 4},
  {"raw": "m. Fie Fi (g. 1° m. Gro Gamma)", "expect": null},
  {"raw": "Søn: g. 1° m. Hans", "expect": null},
  {"raw": "g. m. Ib Iota", "expect": null},
  {"raw": "gift 1 m. Jo Jota", "expect": null},
  {"raw": "g. 1234° m. Kim Kappa", "expect": null},
  {"raw": "", "expect": null}
]
```

- [ ] **Step 2: Fejlende Python-tests** (tilføj til `test_relation_persona_extract_v3.py`):

```python
import json
from pathlib import Path

BOOK_FIXTURE = Path(__file__).resolve().parents[4] / "tests" / "fixtures" / "relation-book-ordinal.json"


def test_book_ordinal_paritet():
    for case in json.loads(BOOK_FIXTURE.read_text(encoding="utf-8")):
        assert v3.book_ordinal(case["raw"]) == case["expect"], case["raw"]


def test_book_ordinal_none():
    assert v3.book_ordinal(None) is None


def test_nummer_modsiger_bog():
    t = "g. 2° m. Bo Beta, f. 1801."
    assert v3.propose(row(t, t, ordinal=1), 1906)["reason"] == "nummer_modsiger_bog"
    assert v3.propose(row(t, t, ordinal=2), 1906)["reason"] != "nummer_modsiger_bog"
```

  `v3`, `row(text, raw, …, ordinal=)` og afskæringsåret 1906 er dem, filen allerede bruger (test_relation_persona_extract_v3.py:7-14). Kontrollér, at stien i `parents[4]` fra `.claude/skills/daa-extract/scripts/` peger på reporoden.

- [ ] **Step 3: Kør dem og se dem fejle.** Run: `python3 -m pytest .claude/skills/daa-extract/scripts/test_relation_persona_extract_v3.py -q -k "book_ordinal or modsiger"`.
  Expected: `AttributeError: … book_ordinal`.

- [ ] **Step 4: Implementér Python.** Tilføj i `relation_persona_extract_v3.py`:
  - nær toppen:

```python
# #244: bogens eget ægteskabsnummer forrest i påstanden (»g. 2°«/»gift 2°«). Eksplicitte klasser, ikke \s/\d (som vinduet).
BOOK_ORDINAL = re.compile(r"^[ \t]*(g[.]|gift)[ \t]*([0-9]{1,3})[ \t]*[°º]")


def book_ordinal(raw: str | None) -> int | None:
    m = BOOK_ORDINAL.match((raw or "").lower())
    return int(m.group(2)) if m else None
```

  - i `_propose` lige efter `if row.get("marriage_ordinal") is None: return {"tok": "U", "reason": "intet_nummer"}`:

```python
    bo = book_ordinal(row.get("raw"))
    if bo is not None and bo != row["marriage_ordinal"]:
        return {"tok": "U", "reason": "nummer_modsiger_bog"}
```

  - `propose_redecide` ændres **ikke**: P-rækkerne fra `relation_persona_v3_input` har ingen `raw` (plan-review). Skriverens værn dækker dem.

- [ ] **Step 5: Python grøn.** Run: hele `test_relation_persona_extract_v3.py`.
  Expected: alle grønne.

- [ ] **Step 6: Fejlende SQL-test** (tilføj til `tests/sql/test-marriage-ordinal-correction.sql`):

```sql
-- Bognummeret: samme liste som tests/fixtures/relation-book-ordinal.json (Python-siden); hold dem ens.
DO $book_ordinal$
DECLARE r record;
BEGIN
  FOR r IN SELECT * FROM (VALUES ('g. 1° m. Anna Alfa',1),('Gift 2° m. Bo Beta',2),('GIFT 3º m. Cia Ceta',3),
      ('  g.  12 ° m. Dan Delta',12),('g.1°m. Eva Epsilon',1),(E'\tgift\t4°',4),('m. Fie Fi (g. 1° m. Gro Gamma)',NULL),
      ('Søn: g. 1° m. Hans',NULL),('g. m. Ib Iota',NULL),('gift 1 m. Jo Jota',NULL),('g. 1234° m. Kim Kappa',NULL),('',NULL)) v(raw,expect)
  LOOP
    IF private.relation_book_ordinal(r.raw) IS DISTINCT FROM r.expect THEN
      RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: bognummer %',r.raw;
    END IF;
  END LOOP;
  IF private.relation_book_ordinal(NULL) IS NOT NULL THEN RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: NULL'; END IF;
  RAISE NOTICE 'OK: bognummer';
END $book_ordinal$;
```

  Tilføj derefter en blok, der beviser værnet i `write_relation_persona`. Den kopierer opbygningen fra `tests/sql/test-relation-persona-writer.sql` linje 1-40 (`f5b_post`, `f5b_claim`, `f5b_profile` og payload `e`) med de to ændringer nedenfor. Kald derefter writeren som den testfil gør (via `pg_temp.f5b_write`), og forvent `REIMPORT_WRITER_RELATION_PERSONA_ORDINAL_BOOK_MISMATCH`:
  - `v_raw:='g. 2° m. Bo Beta, f. 1801, d. 1870.'` som eneste ægteskab i posten, så serverens nummer er 1;
  - payloadens `marriage_ordinal=1`.

```sql
  BEGIN
    PERFORM pg_temp.f5b_write(-24411,v_actor,jsonb_build_array(e));
    RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: værn sprang over';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'REIMPORT_WRITER_RELATION_PERSONA_ORDINAL_BOOK_MISMATCH%' THEN RAISE; END IF;
  END;
```

- [ ] **Step 7: Kør og se den fejle.**
  Expected: `function private.relation_book_ordinal(unknown) does not exist`.

- [ ] **Step 8: Implementér SQL.**
  - I `schema.sql` efter `relation_marriage_ordinals`:

```sql
-- #244: bogens eget ægteskabsnummer forrest i påstanden (»g. 2°«/»gift 2°«); NULL uden. Python-tvilling:
-- relation_persona_extract_v3.book_ordinal; fælles liste tests/fixtures/relation-book-ordinal.json.
CREATE OR REPLACE FUNCTION private.relation_book_ordinal(p_raw text)
RETURNS integer LANGUAGE sql IMMUTABLE STRICT SET search_path=pg_catalog AS $$
  SELECT (regexp_match(lower(p_raw),'^[ \t]*(g[.]|gift)[ \t]*([0-9]{1,3})[ \t]*[°º]'))[2]::integer
$$;
REVOKE ALL ON FUNCTION private.relation_book_ordinal(text) FROM PUBLIC,anon,authenticated,service_role;
```

  - I `write_relation_persona`, inde i `IF v_marriage THEN … END IF` lige efter SPAN-tjekket (schema.sql:~15086–15092). `v_raw` er sat tidligere i funktionen. Tilføj `v_book integer;` i DECLARE.

```sql
    -- #244 (spec §5): bogens »g. N°« må ikke modsige serverens nummer (alle profiler).
    v_book:=private.relation_book_ordinal(v_raw);
    IF v_book IS NOT NULL AND v_book<>v_ordinal THEN
      RAISE EXCEPTION 'REIMPORT_WRITER_RELATION_PERSONA_ORDINAL_BOOK_MISMATCH';
    END IF;
```

  - I `db-migrations.sql` (#244-blokken): `relation_book_ordinal` og den fulde, seneste `write_relation_persona` med værnet.
  - Kontrollér med `diff`, at migrationskroppen og `schema.sql`-kroppen af `write_relation_persona` er identiske:
    `diff <(awk '/FUNCTION private.write_relation_persona/,/^END \$\$;/' schema.sql) <(awk … db-migrations.sql | tail -n <længde>)`.

- [ ] **Step 9: Grøn.** Run: test-filen, `test-relation-persona-writer.sql`, `test-relation-persona-v2.sql` og `test-relation-persona-v3.sql`.
  Expected: `OK: bognummer`, værnet OK, og de eksisterende er grønne.

- [ ] **Step 10: Commit:** `feat(244): bogens »g. N°« som værn i udtræk og skriver`.

---

### Task 3: Rettelsesskriveren, tabellen, constraintet og arkets input

**Files:**
- Modify: `schema.sql`:
  - `interpretation_party.origin` får en navngivet constraint;
  - ny tabel efter `interpretation_party`-blokken (efter `REVOKE ALL ON private.interpretation_party_current …`, ~1335);
  - nye funktioner lige efter `public.red_relation_child_sheet_input` (~15517).
- Modify: `db-migrations.sql` (#244-blokken og `to_regprocedure`-listen), `db-rls.sql` (grant-listen) og `db-verify.sql` (regprocedure-listen plus asserts).
- Modify: `tests/sql/test-marriage-ordinal-correction.sql`.

**Interfaces:**
- Consumes:
  - `relation_marriage_ordinals` og `relation_book_ordinal` (Task 1-2);
  - `pg_temp.f244_post` og `pg_temp.f244_decide_and_bind`/`f244_bind` (Task 1).
- Produces:
  - tabellen `private.marriage_ordinal_correction`;
  - `public.red_ret_aegteskabsnummer(p_interpretation_key uuid,p_expected_party_version integer,p_note text,p_ctx jsonb) RETURNS integer`;
  - `private.marriage_ordinal_correction_input(bigint) RETURNS jsonb`;
  - `public.red_marriage_ordinal_correction_input(bigint) RETURNS jsonb`;
  - kontrakten `relation-ordinal-sheet-input-v1`. Hver række har:
    - `row_no`, `interpretation_key`, `interpretation_version`, `spouse_party_version`;
    - `stored_ordinal`, `new_ordinal`, `book_ordinal`;
    - `family_id`, `family_ordinal`;
    - `principal_named{navn,foedt,post}`, `spouse_named{navn,foedt}`.

- [ ] **Step 1: Fejlende test** (tilføj til test-filen). Blokken følger nedenfor. Hvert fejltilfælde kører i en savepoint-blok (`BEGIN … EXCEPTION … END`) med `GET STACKED DIAGNOSTICS`, som i `test-relation-binding.sql`.

```sql
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
\ir fixtures/marriage-ordinal-244.sql
DO $ret$
DECLARE v_actor uuid:='11000000-0000-0000-0000-000000024421'; s jsonb; m jsonb; v_in jsonb; v_err text; n int;
  ctx jsonb:=jsonb_build_object('basis','human_sheet','sheet_sha256',repeat('a',64),'rows_sha256',repeat('b',64),'line','1');
  k1 uuid; k2 uuid; v int;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) SELECT g,false,false,'244' FROM generate_series(-24429,-24421) g;
  s:=pg_temp.f5b_source(-24421);
  m:=pg_temp.f244_post(-24421,s,'R-1',-24421,-24422,-24423,v_actor);
  k1:=(m->'c1'->>'key')::uuid; k2:=(m->'c2'->>'key')::uuid;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  n:=pg_temp.f244_decide_and_bind(-24421,v_actor);
  IF n<>2 THEN RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: fixture bandt %',n; END IF;
  -- før rettelsen: begge synlige og ALREADY_APPLIED (spec §9.1)
  IF (SELECT count(*) FROM public.public_family_sources(ARRAY[(m->>'f1')::bigint,(m->>'f2')::bigint]) x WHERE x.slags='aegteskab')<>2 THEN
    RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: synlig før';
  END IF;
  IF pg_temp.f244_bind(-24421,v_actor)<>0 THEN RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: før-preview ikke ALREADY_APPLIED'; END IF;
  -- input: begge påstande, gemt ≠ nyt
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  v_in:=red_marriage_ordinal_correction_input(-24421);
  IF jsonb_array_length(v_in->'rows')<>2 OR v_in->>'contract'<>'relation-ordinal-sheet-input-v1'
     OR (SELECT count(*) FROM jsonb_array_elements(v_in->'rows') r
          WHERE (r->>'stored_ordinal')::int<>(r->>'new_ordinal')::int AND (r->>'new_ordinal')::int=(r->>'family_ordinal')::int
            AND (r->>'book_ordinal')::int=(r->>'new_ordinal')::int)<>2 THEN
    RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: input %',v_in;
  END IF;
  -- ret_kontekst: ukendt nøgle, forkert basis, dårlig hash, tom note
  BEGIN PERFORM red_ret_aegteskabsnummer(k1,1,'n',ctx||'{"x":1}'); RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: ukendt nøgle';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'MARRIAGE_ORDINAL_CORRECTION_CONTEXT_INVALID%' THEN RAISE; END IF; END;
  BEGIN PERFORM red_ret_aegteskabsnummer(k1,1,'n',ctx||'{"basis":"web_detail"}'); RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: basis';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'MARRIAGE_ORDINAL_CORRECTION_CONTEXT_INVALID%' THEN RAISE; END IF; END;
  BEGIN PERFORM red_ret_aegteskabsnummer(k1,1,' ',ctx); RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: note';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'MARRIAGE_ORDINAL_CORRECTION_CONTEXT_INVALID%' THEN RAISE; END IF; END;
  -- ret_version
  BEGIN PERFORM red_ret_aegteskabsnummer(k1,2,'n',ctx); RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: version';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'MARRIAGE_ORDINAL_CORRECTION_VERSION_MISMATCH%' THEN RAISE; END IF; END;
  -- gyldig rettelse af begge
  v:=red_ret_aegteskabsnummer(k1,1,'n',ctx);
  PERFORM red_ret_aegteskabsnummer(k2,1,'n',ctx||'{"line":"2"}');
  RESET ROLE;
  IF v<>2 OR (SELECT marriage_ordinal FROM private.interpretation_party_current WHERE interpretation_key=k1 AND party_role='spouse')<>1
     OR (SELECT origin FROM private.interpretation_party_current WHERE interpretation_key=k1 AND party_role='spouse')<>'ordinal_correction'
     OR (SELECT count(*) FROM private.marriage_ordinal_correction WHERE interpretation_key IN (k1,k2))<>2
     OR (SELECT post_offset FROM private.interpretation_party WHERE interpretation_key=k1 AND party_role='spouse' AND version=2)
        IS DISTINCT FROM (SELECT post_offset FROM private.interpretation_party WHERE interpretation_key=k1 AND party_role='spouse' AND version=1)
     OR (SELECT array_agg(ordinal ORDER BY family_id) FROM family_member WHERE person_id=-24421 AND rolle='partner')<>ARRAY[1,2] THEN
    RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: rettelse';
  END IF;
  -- ret_gentaget: samme linje igen → version; ret_ikke_noedvendig: med den nye version → NOT_NEEDED
  SET LOCAL ROLE authenticated;
  BEGIN PERFORM red_ret_aegteskabsnummer(k1,1,'n',ctx); RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: gentaget';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'MARRIAGE_ORDINAL_CORRECTION_VERSION_MISMATCH%' THEN RAISE; END IF; END;
  BEGIN PERFORM red_ret_aegteskabsnummer(k1,2,'n',ctx); RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: ikke nødvendig';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'MARRIAGE_ORDINAL_CORRECTION_NOT_NEEDED%' THEN RAISE; END IF; END;
  IF jsonb_array_length(red_marriage_ordinal_correction_input(-24421)->'rows')<>0 THEN
    RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: input efter';
  END IF;
  RESET ROLE;
  -- genbinding: begge egnede med supersedes, derefter synlige igen
  IF (SELECT count(*) FROM public.public_family_sources(ARRAY[(m->>'f1')::bigint,(m->>'f2')::bigint]) x WHERE x.slags='aegteskab')<>0 THEN
    RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: hul';
  END IF;
  n:=pg_temp.f244_bind(-24421,v_actor);
  IF n<>2 OR (SELECT count(*) FROM private.interpretation_promotion WHERE target_type='family'
               AND interpretation_id IN (SELECT id FROM private.interpretation_current WHERE interpretation_key IN (k1,k2))
               AND evidence->>'supersedes_promotion_id' IS NOT NULL)<>2
     OR (SELECT count(*) FROM public.public_family_sources(ARRAY[(m->>'f1')::bigint,(m->>'f2')::bigint]) x WHERE x.slags='aegteskab')<>2 THEN
    RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: genbinding';
  END IF;
  IF pg_temp.f244_bind(-24421,v_actor)<>0 THEN RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: genkørsel'; END IF;
  -- familiekorroboration (spec §7.5): vejen er stadig lukket for den rettede ægtefælle. Som ejer (funktionen er
  -- REVOKE'et fra authenticated), med gyldig basis, så proveniens-tjekket (a) nås. Fixturens origin_ref er tilfældig,
  -- så (a) afviser også før rettelsen; testen viser kun »stadig lukket« og skelner på partens origin.
  IF (SELECT origin FROM private.interpretation_party_current WHERE interpretation_key=k1 AND party_role='spouse')<>'ordinal_correction' THEN
    RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: origin';
  END IF;
  BEGIN
    PERFORM private.check_family_corroboration((m->>'s1')::uuid,-24422,0,'accepted',
      '{"basis":"family_corroboration","method":"family-corroboration-v1"}'::jsonb);
    RAISE EXCEPTION 'ORDINAL_244_TEST_FAILED: korroboration';
  EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_err=MESSAGE_TEXT;
    IF v_err NOT LIKE 'FAMILY_CORROBORATION_PROVENANCE_INVALID%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'OK: rettelse og genbinding';
END $ret$;
ROLLBACK;
```

  Kontrollér signaturen af `private.check_family_corroboration` (schema.sql:~16066, 5 argumenter) før kørslen.

  Tilføj derefter disse blokke:
  - **`ret_familie_forkert`:** ny post `R-2`; efter afgørelse og binding opdateres `family_member.ordinal` for hovedpersonen i f1 til 3. Forvent `FAMILY_MISMATCH`.
  - **`ret_familie_null`:** samme, men ordinal sat til NULL. Forvent `FAMILY_MISMATCH`.
  - **`ret_bog`:** post `R-3` med `f244_post(…, p_k1=>'Gift 2° m. Bo Beta (søn af Ole Oma) f. 1800.', p_raw1=>'Gift 2° m. Bo Beta f. 1800.')`. Vinduet findes, bogen siger 2, og det nye nummer er 1. Forvent `BOOK_MISMATCH`.
  - **`ret_ikke_bundet`:** post `R-4` med `f244_post`, men uden `f244_decide_and_bind`. Forvent `NOT_BOUND`.
  - **`ret_rolle`:** en aktør med rollen `laeser`, eller `request.jwt.claim.sub` ikke sat. Forvent `EVIDENCE_ROLE_FORBIDDEN`.
  - **`ret_rettigheder`:**
    - `has_function_privilege('anon','public.red_ret_aegteskabsnummer(uuid,integer,text,jsonb)','EXECUTE')` = false;
    - samme for `service_role`;
    - `authenticated` = true;
    - samme tre tjek for wrapperen `public.red_marriage_ordinal_correction_input(bigint)`: false for anon og service_role, true for authenticated;
    - `private.marriage_ordinal_correction_input(bigint)` = false for alle tre.
  - **`ret_tabel`:** UPDATE, DELETE og TRUNCATE på `private.marriage_ordinal_correction` afvises (som ejer, i savepoints).
  - **`ret_origin`:** INSERT af en part med `origin='andet'` afvises af `interpretation_party_origin_check`.

  Låsetesten `ret_venter_paa_soeskende` lægges sidst i filen uden for hovedtransaktionen. Den følger mønstret `$relation_decide_lock$` i `test-relation-binding.sql:251–286` (retning 1 kan køre):
  1. **Committet opsætning** i sin egen transaktion (`BEGIN; \ir …; DO …; COMMIT;`): kilde `-24461`, personer `-24461..-24463`, `f244_post(…, p_third=>true)` og `f244_decide_and_bind`. Den tredje påstand (`'Gift 3° m. Dy Delta.'`, ingen familie) forbliver `proposed`. Opsætningen committes, så `red_decide_relation_interpretations`' `FOR UPDATE` på proposed-rækker ikke længere holdes, når testen kører.
  2. **Positiv kontrol** (uden rettelse). I dblink-sessionen: `BEGIN`, `set_config('request.jwt.claim.sub',<aktør>,true)`, `SET LOCAL ROLE authenticated` og `red_decide_interpretation(<c3-id>,1,'rejected','{…}')`, som skal lykkes. Derefter `ROLLBACK`. Det beviser, at kaldet ellers er tilladt og ikke blokeret.
  3. **Hovedsessionen** åbner en transaktion og kalder `red_ret_aegteskabsnummer(k1,1,…)` som aktøren. Kaldet lykkes og holder låsene, og transaktionen afsluttes ikke endnu.
  4. **dblink-sessionen** (`SET lock_timeout='300ms'`) gentager kaldet fra step 2. Forvent `lock timeout`. Hovedsessionen kører derefter `ROLLBACK`.
  5. **Oprydning** som `test-identity-candidates.sql:236–245`: `SET session_replication_role=replica`, og `DELETE` i FK-orden af alle rækker for kilde `-24461` (promotion → klassifikation → party → interpretation_observation → interpretation → identitet/event → mention/persona → observationer → anchor → occurrence → record → placering/lineage → family_member → family → person → kilde → extraction_run/rendition → profil/auth.users). Til sidst `SET session_replication_role=origin`. Efter oprydningen asserter testen, at der er 0 rækker for kilde `-24461` i `private.interpretation` og `public.family_member` for de tre personer.

- [ ] **Step 2: Kør og se den fejle.**
  Expected: `function red_marriage_ordinal_correction_input(integer) does not exist`.

- [ ] **Step 3: Implementér constraint og tabel** i `schema.sql`:
  - I `CREATE TABLE private.interpretation_party`: `origin text NOT NULL CONSTRAINT interpretation_party_origin_check CHECK (origin IN ('relation_persona','relation_decision','ordinal_correction')),`.
  - Efter `REVOKE ALL ON private.interpretation_party_current …`:

```sql
-- #244 (spec §7.1): rettelse af et skævt gemt ægteskabsnummer i ægtefælleparten. Tilføj-kun; partens origin_ref peger hertil.
CREATE TABLE IF NOT EXISTS private.marriage_ordinal_correction (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  interpretation_key  uuid NOT NULL,
  interpretation_id   uuid NOT NULL REFERENCES private.interpretation(id),
  party_version_from  integer NOT NULL CHECK (party_version_from>=1),
  party_version_to    integer NOT NULL CHECK (party_version_to=party_version_from+1),
  ordinal_from        integer NOT NULL CHECK (ordinal_from>=1),
  ordinal_to          integer NOT NULL CHECK (ordinal_to>=1 AND ordinal_to<>ordinal_from),
  family_id           bigint NOT NULL,
  evidence            jsonb NOT NULL CHECK (jsonb_typeof(evidence)='object' AND evidence<>'{}'::jsonb),
  created_by          uuid NOT NULL,
  created_at          timestamptz NOT NULL DEFAULT clock_timestamp(),
  UNIQUE (interpretation_key,party_version_from)
);
DO $marriage_ordinal_correction_table$
BEGIN
  DROP TRIGGER IF EXISTS trg_marriage_ordinal_correction_append_only ON private.marriage_ordinal_correction;
  CREATE TRIGGER trg_marriage_ordinal_correction_append_only BEFORE UPDATE OR DELETE ON private.marriage_ordinal_correction
    FOR EACH ROW EXECUTE FUNCTION private.reject_evidence_mutation();
  DROP TRIGGER IF EXISTS trg_marriage_ordinal_correction_no_truncate ON private.marriage_ordinal_correction;
  CREATE TRIGGER trg_marriage_ordinal_correction_no_truncate BEFORE TRUNCATE ON private.marriage_ordinal_correction
    FOR EACH STATEMENT EXECUTE FUNCTION private.reject_evidence_mutation();
  ALTER TABLE private.marriage_ordinal_correction ENABLE ROW LEVEL SECURITY;
  REVOKE ALL ON TABLE private.marriage_ordinal_correction FROM PUBLIC,anon,authenticated,service_role;
END $marriage_ordinal_correction_table$;
```

  I `db-migrations.sql` (#244-blokken) lægges før tabellen:

```sql
-- #244 (spec §7.2): tredje oprindelse for ægtefælleparten. Betinget, som relation_classification_event_kind_check.
DO $interpretation_party_origin$
BEGIN
  IF (SELECT pg_get_constraintdef(oid) FROM pg_constraint
       WHERE conrelid='private.interpretation_party'::regclass AND conname='interpretation_party_origin_check')
     IS DISTINCT FROM 'CHECK ((origin = ANY (ARRAY[''relation_persona''::text, ''relation_decision''::text, ''ordinal_correction''::text])))' THEN
    ALTER TABLE private.interpretation_party DROP CONSTRAINT IF EXISTS interpretation_party_origin_check;
    ALTER TABLE private.interpretation_party ADD CONSTRAINT interpretation_party_origin_check
      CHECK (origin IN ('relation_persona','relation_decision','ordinal_correction')) NOT VALID;
    ALTER TABLE private.interpretation_party VALIDATE CONSTRAINT interpretation_party_origin_check;
  END IF;
END $interpretation_party_origin$;
```

  Kontrollér den faktiske `pg_get_constraintdef`-tekst på en frisk base. Afviger formatet, så ret sammenligningsstrengen, ellers kører blokken hver gang. Det er harmløst, men ikke idempotent i ånden.

  Tabelblokken lægges ordret efter. Den er idempotent med `IF NOT EXISTS` og `DROP TRIGGER IF EXISTS`.

- [ ] **Step 4: Implementér skriveren** (schema.sql efter `red_relation_child_sheet_input`, og ordret i #244-blokken):

```sql
-- #244 (spec §7.3-§7.4): retter det gemte ægteskabsnummer i ægtefælleparten for en bundet påstand, kun fra arket.
-- Fortolkningen og afgørelsen røres ikke; genbindingen sker ad 2b-i-vejen (bind-preview ser en ny tilstand).
CREATE OR REPLACE FUNCTION public.red_ret_aegteskabsnummer(p_interpretation_key uuid,p_expected_party_version integer,
  p_note text,p_ctx jsonb)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE v_ctx jsonb:=coalesce(p_ctx,'{}'::jsonb); v_ic private.interpretation%ROWTYPE; v_sp private.interpretation_party%ROWTYPE;
  v_occ uuid; v_principal bigint; v_spouse bigint; v_fam bigint; v_new integer; v_famord integer; v_book integer;
  v_corr uuid:=gen_random_uuid(); v_st jsonb;
BEGIN
  IF auth.uid() IS NULL OR public.current_rolle()<>'redaktion' THEN RAISE EXCEPTION 'EVIDENCE_ROLE_FORBIDDEN'; END IF;
  IF jsonb_typeof(v_ctx)<>'object'
     OR (SELECT array_agg(k COLLATE "C" ORDER BY k COLLATE "C") FROM jsonb_object_keys(v_ctx) k)
        IS DISTINCT FROM ARRAY['basis','line','rows_sha256','sheet_sha256']
     OR v_ctx->>'basis' IS DISTINCT FROM 'human_sheet'
     OR coalesce(v_ctx->>'sheet_sha256','') !~ '^[0-9a-f]{64}$' OR coalesce(v_ctx->>'rows_sha256','') !~ '^[0-9a-f]{64}$'
     OR coalesce(v_ctx->>'line','') !~ '^[1-9][0-9]*$' OR nullif(btrim(p_note),'') IS NULL
     OR p_interpretation_key IS NULL OR p_expected_party_version IS NULL THEN
    RAISE EXCEPTION 'MARRIAGE_ORDINAL_CORRECTION_CONTEXT_INVALID';
  END IF;
  SELECT * INTO v_ic FROM private.interpretation_current WHERE interpretation_key=p_interpretation_key;
  IF NOT FOUND OR v_ic.predicate<>'relation.marriage' THEN RAISE EXCEPTION 'MARRIAGE_ORDINAL_CORRECTION_NOT_BOUND'; END IF;
  -- Låse (spec §7.4): kildelåsen som red_afgoer_relation_interpretation, så postens ikke-afviste ægteskabspåstande
  -- (deres nummer afhænger af hinanden), så personer → familier → medlemmer.
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('daa-identity-candidates:'||v_ic.source_id::text,0));
  SELECT o.occurrence_id INTO v_occ FROM private.interpretation_observation io JOIN private.source_observation o ON o.id=io.observation_id
   WHERE io.interpretation_id=v_ic.id AND io.evidence_role='supporting' AND io.ordinal=1;
  PERFORM 1 FROM private.interpretation i
   WHERE i.id IN (SELECT c.id FROM private.interpretation_current c
                    JOIN private.interpretation_observation io ON io.interpretation_id=c.id AND io.evidence_role='supporting' AND io.ordinal=1
                    JOIN private.source_observation o ON o.id=io.observation_id
                   WHERE c.predicate='relation.marriage' AND c.status<>'rejected' AND o.occurrence_id=v_occ)
   ORDER BY i.id FOR SHARE;
  SELECT * INTO v_ic FROM private.interpretation_current WHERE interpretation_key=p_interpretation_key;
  SELECT * INTO v_sp FROM private.interpretation_party_current WHERE interpretation_key=p_interpretation_key AND party_role='spouse';
  SELECT i.canonical_person_id INTO v_principal FROM private.interpretation_party_current pc
    JOIN private.source_persona_identity i ON i.source_persona_id=pc.source_persona_id AND i.decision_status='accepted'
   WHERE pc.interpretation_key=p_interpretation_key AND pc.party_role='principal';
  SELECT i.canonical_person_id INTO v_spouse FROM private.source_persona_identity i
   WHERE i.source_persona_id=v_sp.source_persona_id AND i.decision_status='accepted';
  PERFORM private.lock_family_rows(ARRAY(SELECT x FROM unnest(ARRAY[v_principal,v_spouse]) x WHERE x IS NOT NULL ORDER BY 1));
  -- Læs igen efter låsene: en samtidig rettelse af samme påstand venter på personlåsen og ser derefter den nye
  -- partversion (VERSION_MISMATCH i stedet for triggerens EVIDENCE_PARTY_VERSION_CONFLICT).
  SELECT * INTO v_ic FROM private.interpretation_current WHERE interpretation_key=p_interpretation_key;
  SELECT * INTO v_sp FROM private.interpretation_party_current WHERE interpretation_key=p_interpretation_key AND party_role='spouse';
  SELECT p.target_id INTO v_fam FROM private.interpretation_promotion p
   WHERE p.interpretation_id=v_ic.id AND p.target_type='family' ORDER BY p.promoted_at DESC,p.id DESC LIMIT 1;
  IF v_ic.status<>'accepted' OR v_ic.decision_evidence->>'method' IS DISTINCT FROM 'family-structure-v1'
     OR v_fam IS NULL OR v_principal IS NULL OR v_spouse IS NULL OR v_sp.source_persona_id IS NULL THEN
    RAISE EXCEPTION 'MARRIAGE_ORDINAL_CORRECTION_NOT_BOUND';
  END IF;
  IF v_sp.version IS DISTINCT FROM p_expected_party_version THEN RAISE EXCEPTION 'MARRIAGE_ORDINAL_CORRECTION_VERSION_MISMATCH'; END IF;
  SELECT o.marriage_ordinal INTO v_new FROM private.relation_marriage_ordinals(v_occ) o WHERE o.interpretation_key=p_interpretation_key;
  IF v_new IS NULL OR v_new=v_sp.marriage_ordinal THEN RAISE EXCEPTION 'MARRIAGE_ORDINAL_CORRECTION_NOT_NEEDED'; END IF;
  SELECT fm.ordinal INTO v_famord FROM public.family_member fm WHERE fm.family_id=v_fam AND fm.person_id=v_principal AND fm.rolle='partner';
  IF v_famord IS NULL OR v_famord<>v_new THEN RAISE EXCEPTION 'MARRIAGE_ORDINAL_CORRECTION_FAMILY_MISMATCH'; END IF;
  v_book:=private.relation_book_ordinal(v_ic.value->>'raw');
  IF v_book IS NOT NULL AND v_book<>v_new THEN RAISE EXCEPTION 'MARRIAGE_ORDINAL_CORRECTION_BOOK_MISMATCH'; END IF;
  INSERT INTO private.marriage_ordinal_correction(id,interpretation_key,interpretation_id,party_version_from,party_version_to,
    ordinal_from,ordinal_to,family_id,evidence,created_by)
  VALUES (v_corr,p_interpretation_key,v_ic.id,v_sp.version,v_sp.version+1,v_sp.marriage_ordinal,v_new,v_fam,
    jsonb_build_object('basis','human_sheet','method','marriage-ordinal-correction-v1','sheet_sha256',v_ctx->>'sheet_sha256',
      'rows_sha256',v_ctx->>'rows_sha256','line',(v_ctx->>'line')::int,'note',btrim(p_note),'book_ordinal',v_book),
    auth.uid());
  INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,marriage_ordinal,post_offset,origin,origin_ref)
  VALUES (p_interpretation_key,'spouse',v_sp.version+1,v_sp.source_persona_id,v_new,v_sp.post_offset,'ordinal_correction',v_corr);
  v_st:=private.relation_binding_state(v_ic.id);
  IF v_st IS NULL OR (v_st#>>'{family,family_id}')::bigint IS DISTINCT FROM v_fam
     OR (v_st->>'book_ordinal')::integer IS DISTINCT FROM (v_st->>'family_ordinal')::integer THEN
    RAISE EXCEPTION 'MARRIAGE_ORDINAL_CORRECTION_STATE_INVALID';
  END IF;
  RETURN v_sp.version+1;
END $$;
REVOKE ALL ON FUNCTION public.red_ret_aegteskabsnummer(uuid,integer,text,jsonb) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.red_ret_aegteskabsnummer(uuid,integer,text,jsonb) TO authenticated;
```

- [ ] **Step 5: Implementér arkets input** (lige efter skriveren, ordret i #244-blokken):

```sql
-- #244 (spec §6): arkets input — bundne ægteskaber, hvor det gemte nummer ≠ serverens. Navne forlader aldrig den private mappe.
CREATE OR REPLACE FUNCTION private.marriage_ordinal_correction_input(p_source_id bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
  WITH c AS (
    SELECT ic.id,ic.interpretation_key AS k,ic.version AS ver,ic.value->>'raw' AS raw,o.occurrence_id AS occ
      FROM private.interpretation_current ic
      JOIN private.interpretation_observation io ON io.interpretation_id=ic.id AND io.evidence_role='supporting' AND io.ordinal=1
      JOIN private.source_observation o ON o.id=io.observation_id
     WHERE ic.source_id=p_source_id AND ic.predicate='relation.marriage' AND ic.status='accepted'
       AND ic.decision_evidence->>'method'='family-structure-v1'
       AND EXISTS (SELECT 1 FROM private.interpretation_promotion p WHERE p.interpretation_id=ic.id AND p.target_type='family')
  ), x AS (
    SELECT c.*,sp.version AS spv,sp.marriage_ordinal AS stored,
           (SELECT mo.marriage_ordinal FROM private.relation_marriage_ordinals(c.occ) mo WHERE mo.interpretation_key=c.k) AS new_ord,
           (SELECT p.target_id FROM private.interpretation_promotion p WHERE p.interpretation_id=c.id AND p.target_type='family'
             ORDER BY p.promoted_at DESC,p.id DESC LIMIT 1) AS fam,
           (SELECT i.canonical_person_id FROM private.interpretation_party_current pc
              JOIN private.source_persona_identity i ON i.source_persona_id=pc.source_persona_id AND i.decision_status='accepted'
             WHERE pc.interpretation_key=c.k AND pc.party_role='principal') AS principal,
           (SELECT i.canonical_person_id FROM private.source_persona_identity i
             WHERE i.source_persona_id=sp.source_persona_id AND i.decision_status='accepted') AS spouse
      FROM c JOIN private.interpretation_party_current sp ON sp.interpretation_key=c.k AND sp.party_role='spouse'
  ), y AS (
    SELECT row_number() OVER (ORDER BY x.k::text COLLATE "C") AS row_no,x.* FROM x WHERE x.new_ord IS DISTINCT FROM x.stored
  )
  SELECT jsonb_build_object('contract','relation-ordinal-sheet-input-v1','source_id',p_source_id,'rows',coalesce(jsonb_agg(
    jsonb_build_object('row_no',y.row_no,'interpretation_key',y.k::text,'interpretation_version',y.ver,
      'spouse_party_version',y.spv,'stored_ordinal',y.stored,'new_ordinal',y.new_ord,
      'book_ordinal',private.relation_book_ordinal(y.raw),'family_id',y.fam,
      'family_ordinal',(SELECT fm.ordinal FROM public.family_member fm WHERE fm.family_id=y.fam AND fm.person_id=y.principal AND fm.rolle='partner'),
      'principal_named',(SELECT jsonb_build_object('navn',pp.visning_navn,'foedt',pp.visning_foedt,
          'post',(SELECT xe.linje||'-'||xe.nr FROM public.person_external_id xe WHERE xe.person_id=pp.id AND xe.source_id=p_source_id))
        FROM public.person pp WHERE pp.id=y.principal),
      'spouse_named',(SELECT jsonb_build_object('navn',ps.visning_navn,'foedt',ps.visning_foedt) FROM public.person ps WHERE ps.id=y.spouse))
    ORDER BY y.row_no),'[]'::jsonb))
  FROM y;
$$;
REVOKE ALL ON FUNCTION private.marriage_ordinal_correction_input(bigint) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.red_marriage_ordinal_correction_input(p_source_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
BEGIN
  IF auth.uid() IS NULL OR public.current_rolle()<>'redaktion' THEN RAISE EXCEPTION 'EVIDENCE_ROLE_FORBIDDEN'; END IF;
  RETURN private.marriage_ordinal_correction_input(p_source_id);
END $$;
REVOKE ALL ON FUNCTION public.red_marriage_ordinal_correction_input(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.red_marriage_ordinal_correction_input(bigint) TO authenticated;
```

- [ ] **Step 6: Lister og asserts.**
  - Tilføj `'public.red_ret_aegteskabsnummer(uuid,integer,text,jsonb)'` og `'public.red_marriage_ordinal_correction_input(bigint)'` i db-rls.sql-listen, db-verify-listen (`::regprocedure`) og migrationernes `to_regprocedure`-liste. Placér dem ved `red_relation_child_sheet_input`.
  - I `db-verify.sql` tilføjes en DO-blok, der fejler med `VERIFY_FAILED: 244 …`, hvis:
    - `private.marriage_ordinal_correction` ikke har `relrowsecurity`;
    - `has_table_privilege` er sand for anon, authenticated eller service_role (SELECT, INSERT, UPDATE eller DELETE);
    - constraintet `interpretation_party_origin_check` mangler, eller dets definition (`pg_get_constraintdef`) ikke indeholder alle tre værdier `relation_persona`, `relation_decision` og `ordinal_correction`.

- [ ] **Step 7: Grøn.**
  - Run: test-filen.
    Expected: `OK: ægteskabsnummer efter vinduet`, `OK: bognummer`, `OK: rettelse og genbinding` og de øvrige blokke OK.
  - Run: `test-relation-binding.sql`, `test-family-sources.sql`, `test-family-corroboration.sql` og `test-relation-child.sql`.
    Expected: grønne.
  - Run: db-verify på en frisk base (`tests/sql/run-db-verify-disposable.sql`).
    Expected: grøn.

- [ ] **Step 8: Commit:** `feat(244): rettelsesskriver og ark-input for skævt gemte ægteskabsnumre`.

---

### Task 4: Arket (Python, rækkescript og e2e)

**Files:**
- Create: `.claude/skills/daa-extract/scripts/relation_ordinal_sheet.py`, `test_relation_ordinal_sheet.py` og `relation_ordinal_rows.sql`.
- Create: `tests/sql/fixtures/relation-ordinal-e2e.sql` og `tests/sql/test-relation-ordinal-sheet.sh`.
- Modify: `.github/workflows/ci.yml`:
  - pytest-listen (linje ~142): tilføj `test_relation_ordinal_sheet.py`;
  - step »Ægteskabsark ende til ende«: tilføj `bash tests/sql/test-relation-ordinal-sheet.sh ci5b_2bii_sheet` efter børnearkets linje.

**Interfaces:**
- Consumes: `public.red_marriage_ordinal_correction_input(bigint)` og `public.red_ret_aegteskabsnummer(...)` (Task 3).
- Produces: CLI'en `relation_ordinal_sheet.py render|sql`. Den udskriver `ARK_OK linjer=<n> uden=<m>` og `SQL_OK b=<n> u=<m>`.

- [ ] **Step 1: Fejlende pytest** `test_relation_ordinal_sheet.py`:

```python
"""#244 (spec §6): ark til rettelse af skævt gemte ægteskabsnumre. Kun opdigtede navne."""
import pytest

import relation_ordinal_sheet as osh
from decision_sheet_core import SheetError

K1, K2, K3 = ("00000000-0000-0000-0000-00000000000" + c for c in "123")


def row(no, key, stored=2, new=1, book=1, fam=1):
    return {"row_no": no, "interpretation_key": key, "interpretation_version": 2, "spouse_party_version": 1,
            "stored_ordinal": stored, "new_ordinal": new, "book_ordinal": book, "family_id": 7, "family_ordinal": fam,
            "principal_named": {"navn": "Anna Alfa", "foedt": "1770", "post": "V-1"},
            "spouse_named": {"navn": "Bo Beta", "foedt": "1768"}}


ROWS = {"contract": "relation-ordinal-sheet-input-v1", "source_id": 1,
        "rows": [row(1, K1), row(2, K2, stored=1, new=2, book=2, fam=2), row(3, K3, new=None, book=None)]}


def test_render():
    t = osh.render_sheet(ROWS)
    assert f"C {K1} 1 : B" in t and f"C {K2} 1 : B" in t and K3 not in t
    assert "# [1] Forælder: Anna Alfa (f. 1770), post V-1 · Ægtefælle: Bo Beta (f. 1768)" in t
    assert "bogens N°: 1 · gemt → nyt: 2 → 1 · familiens nr.: 1" in t
    assert "Ikke på arket: 1" in t


def test_sql_og_tokens():
    lines = osh.parse_sheet(osh.render_sheet(ROWS).replace(f"C {K2} 1 : B", f"C {K2} 1 : U"))
    sql = osh.decision_sql(lines, ROWS, sheet_sha256="a" * 64, rows_sha256="b" * 64)
    assert sql.count("red_ret_aegteskabsnummer(") == 1 and f"'{K1}'::uuid, 1," in sql
    assert '"line": 1' in sql and '"basis": "human_sheet"' in sql


@pytest.mark.parametrize("tok", ["R", "S", "b"])
def test_token_afvist(tok):
    lines = osh.parse_sheet(osh.render_sheet(ROWS).replace(f"C {K1} 1 : B", f"C {K1} 1 : {tok}"))
    with pytest.raises(SheetError, match="SHEET_TOKEN_NOT_ALLOWED"):
        osh.check_sheet(lines, ROWS)


def test_linjefejl():
    t = osh.render_sheet(ROWS)
    with pytest.raises(SheetError, match="SHEET_LINES_MISSING"):
        osh.check_sheet(osh.parse_sheet(t.replace(f"C {K2} 1 : B\n", "")), ROWS)
    with pytest.raises(SheetError, match="SHEET_LINE_DUPLICATE"):
        osh.check_sheet(osh.parse_sheet(t + f"C {K1} 1 : B\n"), ROWS)
    with pytest.raises(SheetError, match="SHEET_LINE_UNKNOWN"):
        osh.check_sheet(osh.parse_sheet(t.replace(f"C {K1} 1 : B", f"C {K1} 9 : B")), ROWS)


def test_kontrakt():
    with pytest.raises(SheetError, match="ROWS_CONTRACT_INVALID"):
        osh.render_sheet({**ROWS, "contract": "x"})
```

- [ ] **Step 2: Se den fejle.** Run: `cd .claude/skills/daa-extract/scripts && python3 -m pytest test_relation_ordinal_sheet.py -q`.
  Expected: `ModuleNotFoundError: relation_ordinal_sheet`.

- [ ] **Step 3: Implementér** `relation_ordinal_sheet.py`:

```python
"""#244 (spec §6): ark til rettelse af skævt gemte ægteskabsnumre — ét hash-bundet ark, B = ret, U = lad stå.

Rækkefil og ark rummer navne; værktøjet printer kun antal og koder. `sql` laver ét afgørelsesscript
(red_ret_aegteskabsnummer med human_sheet-kontekst). Serveren genberegner nummeret og afviser alt andet.
"""
from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from pathlib import Path

from decision_sheet_core import SheetError, require_hex64, sql_literal, verify_bound
from spouse_exception_sheet import _write_private, check_private_path

CONTRACT = "relation-ordinal-sheet-input-v1"
UUID = r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
C_RE = re.compile(rf"^C (?P<key>{UUID}) (?P<ver>[0-9]+) : (?P<tok>\S+)\s*(?:#\s*(?P<note>.*))?$")
LOOSE_RE = re.compile(rf"^C {UUID} ")
TOKENS = {"B", "U"}


@dataclass
class Line:
    key: str
    version: int
    tok: str
    note: str | None


def _rettes(r: dict) -> bool:
    n = r.get("new_ordinal")
    return (n is not None and n != r.get("stored_ordinal") and r.get("family_ordinal") == n
            and r.get("book_ordinal") in (None, n))


def _ok_rows(rows: dict) -> dict[str, dict]:
    if rows.get("contract") != CONTRACT:
        raise SheetError("ROWS_CONTRACT_INVALID")
    return {r["interpretation_key"]: r for r in rows["rows"] if _rettes(r)}


def _linje(no: int, r: dict) -> str:
    p, s = r.get("principal_named") or {}, r.get("spouse_named") or {}
    return (f"# [{no}] Forælder: {p.get('navn') or '?'} (f. {p.get('foedt') or '?'}), post {p.get('post') or '?'}"
            f" · Ægtefælle: {s.get('navn') or '?'} (f. {s.get('foedt') or '?'})")


def render_sheet(rows: dict) -> str:
    ok = sorted(_ok_rows(rows).values(), key=lambda r: r["row_no"])
    uden = len(rows["rows"]) - len(ok)
    out = ["# ================= ÆGTESKABSNUMRE (#244) =================",
           "# Sådan læses arket:",
           "#   - Kun linjerne, der starter med »C«, kan ændres — og kun bogstavet til sidst. Alt med »#« er information.",
           "#   - B = ret det gemte nummer til bogens og familiens · U = lad stå (skriver intet).",
           "#   - Familien og ægtefællen er rigtige; kun nummeret i kilden rettes. Bagefter genbindes i samme familie.",
           "#",
           f"# {len(ok)} linjer (forudfyldt B)"]
    for no, r in enumerate(ok, start=1):
        out.append(_linje(no, r))
        out.append(f"#     bogens N°: {r.get('book_ordinal') or '-'} · gemt → nyt: {r['stored_ordinal']} → {r['new_ordinal']}"
                   f" · familiens nr.: {r['family_ordinal']}")
        out.append(f"C {r['interpretation_key']} {r['spouse_party_version']} : B")
    out += ["#", f"# Ikke på arket: {uden} (nummeret kan ikke rettes entydigt). De står uændret."]
    return "\n".join(out) + "\n"


def parse_sheet(text: str) -> list[Line]:
    lines = []
    for raw in text.splitlines():
        m = C_RE.match(raw)
        if m:
            lines.append(Line(m["key"], int(m["ver"]), m["tok"], m["note"]))
        elif LOOSE_RE.match(raw):
            raise SheetError("SHEET_LINE_INVALID")
    return lines


def check_sheet(lines: list[Line], rows: dict) -> list[tuple[Line, dict]]:
    ok = _ok_rows(rows)
    seen: set[str] = set()
    out = []
    for l in lines:
        if l.tok not in TOKENS:
            raise SheetError("SHEET_TOKEN_NOT_ALLOWED")
        r = ok.get(l.key)
        if r is None or r["spouse_party_version"] != l.version:
            raise SheetError("SHEET_LINE_UNKNOWN")
        if l.key in seen:
            raise SheetError("SHEET_LINE_DUPLICATE")
        seen.add(l.key)
        out.append((l, r))
    if seen != set(ok):
        raise SheetError("SHEET_LINES_MISSING")
    return out


def decision_sql(lines: list[Line], rows: dict, *, sheet_sha256: str, rows_sha256: str) -> str:
    require_hex64(sheet_sha256, rows_sha256)
    todo = [(l, r) for l, r in check_sheet(lines, rows) if l.tok == "B"]
    sql = ["\\set ON_ERROR_STOP on", "BEGIN;", "SET LOCAL standard_conforming_strings=on;", "SET LOCAL TimeZone='UTC';",
           "SET LOCAL search_path=pg_catalog,public,private;",
           "SELECT set_config('request.jwt.claim.sub', :'actor', true) IS NOT NULL AS ok \\g /dev/null",
           "SET LOCAL ROLE authenticated;"]
    tag = sheet_sha256[:12]
    for l, r in todo:
        ctx = {"basis": "human_sheet", "sheet_sha256": sheet_sha256, "rows_sha256": rows_sha256, "line": r["row_no"]}
        note = sql_literal(f"nummerark {tag} række {r['row_no']}" + (f" — {l.note}" if l.note else ""))
        sql.append(f"SELECT red_ret_aegteskabsnummer('{l.key}'::uuid, {l.version}, {note}, "
                   f"{sql_literal(json.dumps(ctx, sort_keys=True))}::jsonb) \\g /dev/null")
    sql.append("COMMIT;")
    return "\n".join(sql) + "\n"


def main() -> int:
    ap = argparse.ArgumentParser()
    sub = ap.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("render")
    s = sub.add_parser("sql")
    for p in (r, s):
        p.add_argument("--rows", required=True)
        p.add_argument("--private-root", default=str(Path.home() / ".private"))
    r.add_argument("--out", required=True)
    for a in ("--sheet", "--approved-sha256", "--expect-rows-sha256", "--decision-out"):
        s.add_argument(a, required=True)
    args = ap.parse_args()
    root = Path(args.private_root)
    try:
        rows_bytes = check_private_path(Path(args.rows), root).read_bytes()
        rows = json.loads(rows_bytes.decode("utf-8"))
        if args.cmd == "render":
            text = render_sheet(rows)
            _write_private(check_private_path(Path(args.out), root), text)
            ok = _ok_rows(rows)
            print(f"ARK_OK linjer={len(ok)} uden={len(rows['rows']) - len(ok)}")
            return 0
        dout = check_private_path(Path(args.decision_out), root)
        sheet_bytes = check_private_path(Path(args.sheet), root).read_bytes()
        rows_sha, sheet_sha = verify_bound(rows_bytes, args.expect_rows_sha256, sheet_bytes, args.approved_sha256)
        lines = parse_sheet(sheet_bytes.decode("utf-8"))
        sql = decision_sql(lines, rows, sheet_sha256=sheet_sha, rows_sha256=rows_sha)
        _write_private(dout, sql)
        toks = [l.tok for l in lines]
    except SheetError as exc:
        print(str(exc).split(" ")[0])
        return 1
    print(f"SQL_OK b={toks.count('B')} u={toks.count('U')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

  Og `relation_ordinal_rows.sql`:

```sql
-- #244 (spec §6): rækkefil til nummerarket. Indeholder navne → 0600 under ~/.private/244/.
-- Kør:  PGCLIENTENCODING=UTF8 psql -XAtq -v actor=… -v source=1 -f relation_ordinal_rows.sql > rows.json
-- Rækkefilen er præcis projektionens ::text + én LF.
\set ON_ERROR_STOP on
BEGIN;
SET TRANSACTION READ ONLY;
SET LOCAL TimeZone='UTC';
SELECT set_config('request.jwt.claim.sub', :'actor', true) IS NOT NULL AS ok \g /dev/null
SET LOCAL ROLE authenticated;
SELECT public.red_marriage_ordinal_correction_input(:source)::text;
ROLLBACK;
```

- [ ] **Step 4: Pytest grøn.** Run: `python3 -m pytest test_relation_ordinal_sheet.py -q`.
  Expected: alle grønne.

- [ ] **Step 5: E2e-fixturen** `tests/sql/fixtures/relation-ordinal-e2e.sql`. Den committes i engangsbasen.

```sql
-- #244 Task 4: data til nummerarkets ende-til-ende-test. Opdigtede navne. To ægteskaber i én post, afgjort og bundet
-- med det gamle fejlnummer gemt (1↔2), som de 4 i 2018-20.
\set ON_ERROR_STOP on
BEGIN;
\ir relation-5b.sql
\ir relation-2a.sql
\ir marriage-ordinal-244.sql
DO $ordinal_e2e_fixture$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000000244e2'; s jsonb; m jsonb;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status,visning_navn,visning_foedt) VALUES
    (-24451,false,false,'244','Anna Alfa','1770'),(-24452,false,false,'244','Bo Beta','1768'),(-24453,false,false,'244','Cia Ceta','1775');
  s:=pg_temp.f5b_source(-24451);
  m:=pg_temp.f244_post(-24451,s,'E-1',-24451,-24452,-24453,v_actor);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF pg_temp.f244_decide_and_bind(-24451,v_actor)<>2 THEN RAISE EXCEPTION 'ORDINAL_E2E_FIXTURE_FAILED'; END IF;
END $ordinal_e2e_fixture$;
COMMIT;
```

- [ ] **Step 6: E2e-scriptet** `tests/sql/test-relation-ordinal-sheet.sh`:

```bash
#!/usr/bin/env bash
# #244 (spec §6, §9): nummerarket ende til ende i en engangsbase — input → ark → hash → afgørelsesscript → rettelser →
# preview (2 genbindinger). Printer kun antal og koder.
set -euo pipefail
db=${1:?database}
actor=11000000-0000-0000-0000-0000000244e2
root=$(mktemp -d); chmod 700 "$root"; trap 'rm -rf "$root"' EXIT
sd=.claude/skills/daa-extract/scripts
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$db" "$@"; }
q -f tests/sql/fixtures/relation-ordinal-e2e.sql >/dev/null
PGCLIENTENCODING=UTF8 env -u PGOPTIONS psql -X -Atq -v ON_ERROR_STOP=1 -v actor="$actor" -v source=-24451 -d "$db" \
  -f $sd/relation_ordinal_rows.sql > "$root/rows.json"
[ "$(python3 $sd/relation_ordinal_sheet.py render --rows "$root/rows.json" --out "$root/ark.txt" --private-root "$root")" \
  = "ARK_OK linjer=2 uden=0" ]
rows_sha=$(shasum -a 256 "$root/rows.json" | cut -d' ' -f1); ark_sha=$(shasum -a 256 "$root/ark.txt" | cut -d' ' -f1)
# Negativ: rettet efter godkendelsen → hash afvist, ingen fil.
sed 's/ : B$/ : U/' "$root/ark.txt" > "$root/ark-neg.txt"
[ "$(python3 $sd/relation_ordinal_sheet.py sql --rows "$root/rows.json" --sheet "$root/ark-neg.txt" --approved-sha256 "$ark_sha" \
     --expect-rows-sha256 "$rows_sha" --decision-out "$root/neg.sql" --private-root "$root" || true)" = "SHEET_HASH_MISMATCH" ]
[ ! -e "$root/neg.sql" ]
# Negativ: R er ikke et gyldigt svar her.
sed 's/ : B$/ : R/' "$root/ark.txt" > "$root/ark-r.txt"; r_sha=$(shasum -a 256 "$root/ark-r.txt" | cut -d' ' -f1)
[ "$(python3 $sd/relation_ordinal_sheet.py sql --rows "$root/rows.json" --sheet "$root/ark-r.txt" --approved-sha256 "$r_sha" \
     --expect-rows-sha256 "$rows_sha" --decision-out "$root/r.sql" --private-root "$root" || true)" = "SHEET_TOKEN_NOT_ALLOWED" ]
[ ! -e "$root/r.sql" ]
[ "$(python3 $sd/relation_ordinal_sheet.py sql --rows "$root/rows.json" --sheet "$root/ark.txt" --approved-sha256 "$ark_sha" \
     --expect-rows-sha256 "$rows_sha" --decision-out "$root/d.sql" --private-root "$root")" = "SQL_OK b=2 u=0" ]
q -v actor="$actor" -f "$root/d.sql" >/dev/null
q -At <<SQL | grep -qx 't'
SELECT (SELECT count(*) FROM private.marriage_ordinal_correction c
         WHERE c.evidence->>'sheet_sha256'='$ark_sha' AND c.family_id IN (SELECT family_id FROM family_member WHERE person_id=-24451))=2;
SQL
q -At -v actor="$actor" <<'SQL' | grep -qx '2'
BEGIN;
SELECT coalesce(jsonb_agg(jsonb_build_object('interpretation_id',ic.id::text,
         'family_id',(private.relation_binding_state(ic.id)#>>'{family,family_id}')::bigint)),'[]')::text AS items
  FROM private.interpretation_current ic WHERE ic.source_id=-24451 AND ic.status='accepted' \gset
SELECT set_config('request.jwt.claim.sub', :'actor', true) \g /dev/null
SET LOCAL ROLE authenticated;
SELECT count(*) FROM jsonb_array_elements(public.red_preview_relation_promotions(-24451,:'items'::jsonb)->'items') i
 WHERE (i->>'eligible')::boolean AND i->>'supersedes_promotion_id' IS NOT NULL;
ROLLBACK;
SQL
echo ORDINAL_SHEET_E2E_OK
```

- [ ] **Step 7: Kør e2e.** Byg engangsbasen som CI-steppet »Ægteskabsark ende til ende«, og kør scriptet.
  Expected: `ORDINAL_SHEET_E2E_OK`. Fejler `verify_bound` med en anden kode end `SHEET_HASH_MISMATCH`, så slå den faktiske kode op i `decision_sheet_core.verify_bound`, ret forventningen, og skriv en ruling.

- [ ] **Step 8: Commit:** `feat(244): nummerark (render, sql, e2e)`. Filerne er script, test, rows-sql, fixture, e2e og ci.yml.

---

### Task 5: Opgradering og fuld lokal CI

**Files:**
- Create: `tests/sql/test-244-upgrade.sh`. Den kører kun lokalt, som `test-2bii-upgrade.sh`, der heller ikke kører i CI. Spec §9.1 nævner en CI-kobling. Planen følger repo'ets mønster, og det skrives som ruling.

- [ ] **Step 1: Skriv opgraderingstesten:**

```bash
#!/usr/bin/env bash
# #244 (spec §9.1): opgradering fra main (før #244): gammel funktion og unavngivet origin-CHECK løftes; migrationerne
# køres to gange; testfilen og db-verify skal være grønne bagefter. Kun lokalt.
set -euo pipefail
db=${1:?database}; base=${2:-$(git merge-base origin/main HEAD)}
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
for f in schema.sql db-rls.sql db-migrations.sql; do git show "$base:$f" > "$tmp/$f"; done
q() { env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d "$db" "$@" >/dev/null; }
createdb "$db"
for f in tests/sql/evidence-promotion-bootstrap.sql "$tmp/schema.sql" "$tmp/db-rls.sql" "$tmp/db-migrations.sql" "$tmp/db-migrations.sql" "$tmp/db-rls.sql"; do q -f "$f"; done
[ "$(env -u PGOPTIONS psql -X -At -d "$db" -c "SELECT count(*) FROM pg_constraint WHERE conname='interpretation_party_origin_check'")" = "1" ]
for f in db-migrations.sql db-rls.sql db-migrations.sql db-rls.sql; do q -f "$f"; done
[ "$(env -u PGOPTIONS psql -X -At -d "$db" -c "SELECT pg_get_constraintdef(oid) LIKE '%ordinal_correction%' FROM pg_constraint WHERE conname='interpretation_party_origin_check'")" = "t" ]
q -f tests/sql/1939-v50-writer-bootstrap.sql
q -c 'BEGIN' -f tests/sql/reimport-writer-v2-bootstrap.sql -c 'COMMIT'
q -f db-rls.sql
q -f tests/sql/test-marriage-ordinal-correction.sql
db="${1}_v"; createdb "$db"
for f in tests/sql/evidence-promotion-bootstrap.sql "$tmp/schema.sql" "$tmp/db-rls.sql" "$tmp/db-migrations.sql" "$tmp/db-migrations.sql" "$tmp/db-rls.sql" \
         db-migrations.sql db-rls.sql db-migrations.sql db-rls.sql tests/sql/run-db-verify-disposable.sql; do q -f "$f"; done
echo UPGRADE_OK
```

  **Opbygning af writer-basen.** Ingen eksisterende opgraderingstest kører writer-bootstrappene (`1939-v50-writer-bootstrap.sql`, `reimport-writer-v2-bootstrap.sql`) på en migreret base. Testfilen kræver kontrakt 2 (skriveren og publiceringen). Derfor:
  - **Prøvekør først** bootstrappene på den migrerede base.
  - **Hvis de virker,** beholdes scriptet som ovenfor.
  - **Hvis de fejler,** deles testfilen i to:
    - en kontraktuafhængig kerne `tests/sql/test-marriage-ordinal-core.sql` med `relation_book_ordinal`-listen, rettighedstjekkene, tabellens tilføj-kun-tjek og constraint-tjekket;
    - den fulde fil, som kun kører på frisk schema i CI.

    Opgraderingstesten kører så kun kernen, og det skrives som ruling.
  - **Rækkefølgen** følger `test-2bii-upgrade.sh`: den gamle base' migrationer køres **to gange** (`"$tmp/db-migrations.sql" "$tmp/db-migrations.sql"`), før de nye køres to gange.

- [ ] **Step 2: Kør:** `bash tests/sql/test-244-upgrade.sh t244_upg`.
  Expected: `UPGRADE_OK`. Ryd `t244_upg` og `t244_upg_v` op bagefter med `dropdb`. Det er engangsbaser, som scriptet selv har oprettet.

- [ ] **Step 3: Fuld lokal CI.** Kør `run_all.sh` (skabelon fra 2b-iii-workspacet) for alle 7 jobs.
  Expected: 7 × `CI_JOB_OK`.

- [ ] **Step 4: Commit:** `test(244): opgraderingstest fra main`.

---

### Task 6: Bevis i restore og dokumenter

**Files:**
- Create: `docs/evidensbaseret-genimport/aegteskabsnumre-244-bevis.md`.
- Modify:
  - `docs/evidensbaseret-genimport/status.md` og `docs/changelog.md`;
  - `docs/decisions.md` (ny post øverst, plus en erratum-linje ved 2026-10-20 pkt. 4);
  - `docs/evidensbaseret-genimport/relationspersonas-5b-navneregel-v3-bevis.md` (erratum ved fund 1).
- Privat: `~/.private/244/` (0700).

- [ ] **Step 1: Kopibase.** Opret `daa244_bevis_<stempel>` som kopi (`createdb -T`) af `daa5b_2b_iii_bevis_20261020182757`, som ikke ændres. Løft kopien med `db-migrations.sql` og `db-rls.sql`, og log til `~/.private/244/`. Mål tiden (som ejer, `\timing`) for `relation_persona_input(1)` og for previewet i `bind-preview.sql` i originalen og i kopien.
  Expected: kopien højst 2 × originalen og højst 10 s, for begge.

- [ ] **Step 2: Før-målinger.** Kopiér `antal.sql`, `hashes.sql`, `univers.sql`, `read.sql`, `bind-preview.sql` og `bind.sql` fra `~/.private/5b-2b-iii/` til `~/.private/244/`. Kør `antal.sql`, `hashes.sql`, `univers.sql`, `read.sql` og `bind-preview.sql` (kun preview, **ikke** `bind.sql`, der ville kaste `ALREADY_APPLIED`), og gem `foer-*.txt`.

  **2a-digesten.** Kontrollér først, hvilken udvælgelse `hashes.sql` og `univers.sql` bruger til `tupel_digest_2a`, og notér det i rapporten. `univers.sql` udvælger rækker uden nøglen `supersedes_promotion_id`. Promote skriver altid nøglen, med JSON-null ved første binding, så udvælgelsen giver rækkerne fra før 2b-i. Genbindingen skriver nøglen, og digesten er derfor uændret. Er udvælgelsen en anden, så ændres forventningen til »ændret i 2 tupler« (de 2 ældste af de 4), og det skrives som ruling. Kør desuden disse tællinger (kun tal):
  - bundne ægteskaber med en anden metode end `family-structure-v1`;
  - ægtefælleidentiteter for arkets påstande med status `accepted`;
  - gældende bindinger med `book_ordinal≠family_ordinal`;
  - antal fortolkninger, hvis seneste binding har hash = den gældende tilstands;
  - en digest over de gældende bindinger;
  - antallet af »N°«, der er lig serverens nummer.

  Forventet efter løftet, i samme rækkefølge:
  - bundne ægteskaber med anden metode: 0;
  - ægtefælleidentiteter `accepted`: 4 af 4;
  - `book≠family`: 4;
  - fortolkninger med gældende binding: **253**;
  - digesten: noteres;
  - »N°« lig serverens nummer: 40 af 40.

  Løftet ændrer ingen bindingstilstand, fordi tilstandens `book_ordinal` læser det gemte nummer i parten og ikke funktionen. Er antallet af gældende bindinger ikke 253, så stop og skriv en ruling.
- [ ] **Step 3: Arket.**
  1. Lav rækkefilen med `relation_ordinal_rows.sql` (aktør: første redaktion-profil, filtrér uuid'en fra output).
  2. Kør `render`.
     Expected: `ARK_OK linjer=4 uden=0`.
  3. **STOP:** projektejeren åbner arket med `open -e ~/.private/244/ark.txt` og godkender det. Hash arket bagefter (`shasum -a 256`) og notér hashen.
  4. Kør `sql`.
     Expected: `SQL_OK b=4 u=0`.
- [ ] **Step 4: Anvend og mål imellem.** Kør afgørelsesscriptet. Mål derefter:
  - nye partversioner og korrektionsrækker: 4 / 4;
  - inputtet: 0 rækker;
  - læsning: ægteskabskilderækker 4 færre;
  - gældende bindinger: 249.
- [ ] **Step 5: Genbind.** Kør `bind-preview.sql`.
  Expected: 4 egnede, alle med `supersedes`, og 249 `ALREADY_APPLIED`.

  Kør `bind.sql` med manifestet, og kør det derefter igen.
  Expected: første kørsel giver 4 nye rækker; anden kørsel giver 253 `ALREADY_APPLIED` og 0 egnede.
- [ ] **Step 6: Efter-målinger.** Kør alle scripts fra step 2 igen. De forventede værdier står i spec §9.2:
  - kanoniske tabeller og `family_member.ordinal` er uændrede;
  - 2a's digest er uændret, fordi `univers.sql` udvælger rækker uden nøglen `supersedes_promotion_id`, og de nye rækker har nøglen;
  - digesten over de gældende bindinger er ændret i præcis 4 tupler;
  - `book≠family` er 0;
  - universet er 272;
  - læsningen er som før;
  - »N°« stemmer 40 af 40.
- [ ] **Step 7: Negativtests** i en ekstra kopi `daa244_bevis_<stempel>_neg`, i et script `neg.sh`, med log til `neg.log`:
  - forkert arkhash → `SHEET_HASH_MISMATCH`;
  - `R` → `SHEET_TOKEN_NOT_ALLOWED`;
  - direkte kald på en påstand, hvor gemt = nyt → `…_NOT_NEEDED`;
  - samme afgørelsesscript kørt to gange → `…_VERSION_MISMATCH`.

  Omdøb derefter kopien til `slet_<MMDD>__244_bevis_<stempel>_neg`. Mål størrelsen, og skriv manifest i `karantaene-<MMDD>.txt`. Den slettes ikke.
- [ ] **Step 8: Dokumenter.**
  - **Rapporten** skal kun indeholde tal, hashes og basenavne. Den følger 2b-iii-rapportens form og har afsnittene kort svar, grundlag, erratum, arket, rettelse og binding, kontrolmålinger, negativtests, fund og afvigelser.
  - **Statusrække og changelog-post.**
  - **Beslutningspost** »#244: ægteskabsnummeret efter skriverens vindue; 4 numre rettet på ark; afløser pkt. 4's ›genafgør‹«.
  - **Erratum-linjer** i runde 2-rapporten (fund 1) og ved `decisions.md` pkt. 4. Teksten er: »Rettet 2026-10-20 (#244): årsagen er en parentes midt i klausulen, ikke en overskreden klausulgrænse; se aegteskabsnumre-244-bevis.md«.
- [ ] **Step 9: Issue.** Ret beskrivelsen af #244 med `gh issue edit 244 --body-file …`. Den nye tekst har det rigtige afsnit om årsagen og en henvisning til spec og rapport. Ret ikke titlen, før projektejeren har sagt ja. Teksten må ikke indeholde navne.
- [ ] **Step 10: Commit:** `docs(244): bevis i restore, status, beslutning og errata`.

---

## Self-Review

- **Spec-dækning:**

  | Spec | Plan |
  | --- | --- |
  | §4 | Task 1 |
  | §5 | Task 2 |
  | §6 | Task 3 step 5 og Task 4 |
  | §7.1 og §7.2 | Task 3 step 3 og 6 |
  | §7.3 og §7.4 | Task 3 step 4 og låsetesten |
  | §7.5 | Task 3, korroborationsblokken |
  | §8 | Task 3, genbindingsblokken, og Task 6 step 5 |
  | §9.1 | Task 1-5 |
  | §9.2 og §9.3 | Task 6 |
  | §9.4 | Task 6 step 8-9 |
  | §10 | Rapportens afsnit om begrænsninger |

- **Afvigelse fra spec:** opgraderingstesten kører kun lokalt (Task 5), som repo'ets eksisterende opgraderingstests. Det skrives som ruling.
- **Navne:** følgende navne er ens i Task 1-4:
  - `relation_book_ordinal`, `book_ordinal` og `red_ret_aegteskabsnummer(uuid,integer,text,jsonb)`;
  - `red_marriage_ordinal_correction_input(bigint)` og kontrakten `relation-ordinal-sheet-input-v1`;
  - rækkefelterne `spouse_party_version`, `stored_ordinal`, `new_ordinal`, `book_ordinal` og `family_ordinal`.
- **Steder, hvor implementøren skal slå op i koden og skrive en ruling ved afvigelse:**
  - navne i den eksisterende v3-test;
  - signaturen af `public_family_sources`;
  - kaldet af familiekorroborationen;
  - CI's opbygning af `writer_1939`;
  - `verify_bound`'s fejlkode.

  De er markeret i de enkelte trin.
