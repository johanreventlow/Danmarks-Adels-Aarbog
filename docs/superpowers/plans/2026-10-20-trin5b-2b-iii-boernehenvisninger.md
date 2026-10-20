# Trin 5b 2b-iii — børnehenvisningerne binder til familien: implementeringsplan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** De 14 `relation.child`-påstande i DAA 2018-20 afgøres på ét hash-bundet ark og bindes som kildehenvisning på forælderens familie. Læseren ser kilden i web ved børnene og ved forælderen.

**Architecture:** Arbejdet er bygget af disse dele:
- **Parser og regel:** én SQL-parser (`private.relation_child_ref`) og én regelfunktion (`private.relation_child_rule`). Writeren, bindingstilstanden og arkets projektion deler dem, så reglen kun findes ét sted.
- **Writer:** får en selvstændig gren for `relation.child` (`private.decide_relation_child`).
- **Binding:** `relation_binding_state` genberegner reglen mod familien, som den ser ud nu.
- **Læser:** `public_family_sources` giver `slags='boern'`.
- **Ark:** genbruger 2b-ii's mekanik (`decision_sheet_core`).
- **Web:** core og `DetailPanel` viser kilden.

**Tech Stack:** PostgreSQL 17 (plpgsql), Python 3 (ark og pytest), TypeScript/React (vitest), bash-e2e.

**Spec:** `docs/superpowers/specs/2026-10-20-trin5b-2b-iii-boernehenvisninger-design.md` (GODKENDT 2026-10-20). Hovedspecen §22.9 og 2a-specen er baggrund.

## Global Constraints

- Kun restore. Ingen prod-mutation, intet push uden et udtrykkeligt ja, og PR'er altid `--draft`.
- Ingen nye tabeller (spec §1). Ingen `child`-part (spec §6). `p_family_id` er altid NULL for `relation.child`.
- `unresolved` afvises for `relation.child` (spec §6). Arkets `U` skriver intet.
- Alle regelsammenligninger skal være NULL-sikre (`IS [NOT] DISTINCT FROM`/`coalesce(…,false)`, spec §5).
- `schema.sql` er source of truth. `db-migrations.sql` får idempotente kopier i en blok over `-- 5b-sektionen slutter her …`.
- Fejlkoder: `RELATION_CHILD_RULE_NOT_MET`, `RELATION_DECISION_INVALID`, `SHEET_TOKEN_NOT_ALLOWED`, `SHEET_LINE_UNKNOWN`, `SHEET_LINES_MISSING`, `SHEET_LINE_DUPLICATE`, `ROWS_CONTRACT_INVALID`.
- **PII:** navne og bogens tekst må kun forekomme i `~/.private/5b-2b-iii/` (0700/0600). Rapporter, commits og chat indeholder kun tal og hashes. Opdigtede navne i tests.
- Commits: atomiske danske Conventional Commits med trailer `Claude-Session: https://claude.ai/code/session_011rKEYw62xDPse4zhLARtjo`, uden Claude-attribution.
- Kør `env -u PGOPTIONS` foran psql i tests (NOTICE-tests og PGOPTIONS, jf. memory).

## Review Focus

1. Henvisning med enkelt nummer (»Datter: … nr. 119«): `nr_to` skal være lig `nr_from`, ellers slipper H5 igennem med NULL. Låses af `test_ref_enkelt_nummer` i Task 1 og af H5-testen i Task 2.
2. Barn tilføjet mellem afgørelse og binding: preview skal genberegne reglen. Et barn uden egen post bindes, men et barn med egen post uden for intervallet afvises. Låses i Task 3.
3. Børnekilde for en familie med et ikke-offentligt medlem: `public_family_sources` må ikke vise den for `anon`. Låses i Task 3.
4. Ark med en linje for en påstand, der bryder H, eller med et ukendt token: Python afviser med 0 filer. Låses i Task 4.
5. Barnets panel viser kun kilden ved forælderen, der er modpart, ikke ved den anden forælder. Låses i Task 5.

---

### Task 1: Henvisningsparseren `private.relation_child_ref`

**Files:**
- Modify: `schema.sql`. Indsæt umiddelbart før `CREATE OR REPLACE FUNCTION private.relation_structural_candidates` (grep efter navnet).
- Modify: `db-migrations.sql`: ny blok over `-- 5b-sektionen slutter her`.
- Create: `tests/sql/test-relation-child.sql` (parserdelen; Task 2-3 udvider filen).
- Modify: `.github/workflows/ci.yml`: tilføj `test-relation-child` i løkken `for t in test-relation-persona-v2 …` (step »Ordvindue, relation_person_create og disposition SQL«).

**Interfaces:**
- Produces: `private.relation_child_ref(p_raw text) RETURNS jsonb`, IMMUTABLE. Resultatet er `{count:int, sex:'kvinde'|'mand'|null, uncertain:bool, gen_local:int|null, gen_through:int|null, section:text|null, nr_from:int|null, nr_to:int|null}`, eller NULL når teksten ikke følger grammatikken.

- [ ] **Step 1: Skriv den fejlende test.** Opret `tests/sql/test-relation-child.sql`:

```sql
-- Trin 5b 2b-iii (spec 2026-10-20): børnehenvisninger. Kun opdigtede navne. Kører i writer-1939-v50-db.
\set ON_ERROR_STOP on
BEGIN;
DO $child_ref$
DECLARE r jsonb;
BEGIN
  -- interval, slægtled, romertal
  r:=private.relation_child_ref('12 børn: Tolvte slægtled, III, nr. 34-45');
  IF r IS DISTINCT FROM '{"count":12,"sex":null,"uncertain":false,"gen_local":12,"gen_through":null,"section":"III","nr_from":34,"nr_to":45}'::jsonb THEN
    RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: interval %',r; END IF;
  -- test_ref_enkelt_nummer: Datter, enkelt nummer ⇒ nr_to=nr_from, køn kvinde
  r:=private.relation_child_ref('Datter: Fjortende slægtled, V, nr. 119');
  IF r->>'count'<>'1' OR r->>'sex'<>'kvinde' OR r->>'nr_from'<>'119' OR r->>'nr_to'<>'119' THEN
    RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: enkelt nummer %',r; END IF;
  -- parentes-slægtled, U+2011-bindestreg, intet romertal, punktum
  r:=private.relation_child_ref(E'9 børn: Andet (femtende) slægtled, nr. 1‑8.');
  IF r->>'gen_local'<>'2' OR r->>'gen_through'<>'15' OR r->>'section' IS NOT NULL OR r->>'nr_to'<>'8' THEN
    RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: parentes %',r; END IF;
  -- uden henvisning, usikker, sønner
  r:=private.relation_child_ref('3 sønner (?)');
  IF r->>'count'<>'3' OR r->>'sex'<>'mand' OR NOT (r->>'uncertain')::boolean OR r->>'nr_from' IS NOT NULL THEN
    RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: usikker %',r; END IF;
  IF private.relation_child_ref('17 børn')->>'count'<>'17' THEN RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: kun antal'; END IF;
  -- uden for grammatikken ⇒ NULL
  IF private.relation_child_ref('X') IS NOT NULL OR private.relation_child_ref('se nedenfor') IS NOT NULL
     OR private.relation_child_ref('2 børn: Tolvte slægtled, III, nr. 9-3') IS NOT NULL      -- omvendt interval
     OR private.relation_child_ref('2 børn: Hundrede slægtled, III, nr. 1-2') IS NOT NULL   -- ukendt ordenstal
     OR private.relation_child_ref('0 børn') IS NOT NULL
     OR private.relation_child_ref('300 børn: Andet slægtled, I, nr. 1-300') IS NOT NULL    -- urimeligt interval
     OR private.relation_child_ref(NULL) IS NOT NULL THEN
    RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: uden for grammatikken'; END IF;
END $child_ref$;
ROLLBACK;
\echo RELATION_CHILD_TEST_OK
```

- [ ] **Step 2: Kør testen, og se den fejle.** Byg en testbase med scratchpad-hjælperen og kør:

`$SCRATCH` er sessionens scratchpad. `mkdb.sh <db> writer` bygger en base som CI-jobbet `writer-1939-v50-db`.

Run: `bash $SCRATCH/mkdb.sh ci5b_child writer && env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d ci5b_child -f tests/sql/test-relation-child.sql`
Expected: FAIL med `function private.relation_child_ref(unknown) does not exist`.

- [ ] **Step 3: Implementér i `schema.sql`** (før `private.relation_structural_candidates`):

```sql
-- Trin 5b 2b-iii (#151, spec 2026-10-20 §4): bogens børnehenvisning »N børn: <ordenstal> [(<ordenstal>)] slægtled,
-- [<romertal>,] nr. a[–b]«. Deterministisk; ingen model læser teksten. NULL = ikke på formen.
CREATE OR REPLACE FUNCTION private.relation_child_ref(p_raw text)
RETURNS jsonb LANGUAGE plpgsql IMMUTABLE SET search_path=pg_catalog AS $$
DECLARE
  m text[]; v_count integer; v_gl integer; v_gt integer; v_from integer; v_to integer;
  v_ord constant text[]:=ARRAY['første','andet','tredje','fjerde','femte','sjette','syvende','ottende','niende','tiende',
    'ellevte','tolvte','trettende','fjortende','femtende','sekstende','syttende','attende','nittende','tyvende'];
BEGIN
  IF p_raw IS NULL THEN RETURN NULL; END IF;
  m:=regexp_match(btrim(p_raw),
    '^(?:([0-9]{1,3}) (børn|døtre|sønner)|(Datter|Søn))( \(\?\))?'
    '(?::\s*([[:alpha:]]+)(?: \(([[:alpha:]]+)\))? slægtled,(?: ([IVX]+),)? nr\. ([0-9]{1,4})(?:\s*[-‑–]\s*([0-9]{1,4}))?\.?)?$');
  IF m IS NULL THEN RETURN NULL; END IF;
  v_count:=coalesce(m[1]::integer,1);
  IF v_count<1 THEN RETURN NULL; END IF;
  IF m[5] IS NOT NULL THEN
    v_gl:=array_position(v_ord,lower(m[5]));
    IF v_gl IS NULL THEN RETURN NULL; END IF;
  END IF;
  IF m[6] IS NOT NULL THEN
    v_gt:=array_position(v_ord,lower(m[6]));
    IF v_gt IS NULL THEN RETURN NULL; END IF;
  END IF;
  IF m[8] IS NOT NULL THEN
    v_from:=m[8]::integer; v_to:=coalesce(m[9]::integer,v_from);   -- enkelt nummer ⇒ nr_to = nr_from (Review Focus 1)
    IF v_to<v_from OR v_to-v_from>=200 THEN RETURN NULL; END IF;
  END IF;
  RETURN jsonb_build_object('count',v_count,
    'sex',CASE coalesce(m[2],m[3]) WHEN 'døtre' THEN 'kvinde' WHEN 'Datter' THEN 'kvinde'
                                   WHEN 'sønner' THEN 'mand' WHEN 'Søn' THEN 'mand' END,
    'uncertain',m[4] IS NOT NULL,'gen_local',v_gl,'gen_through',v_gt,'section',m[7],'nr_from',v_from,'nr_to',v_to);
END $$;
REVOKE ALL ON FUNCTION private.relation_child_ref(text) FROM PUBLIC,anon,authenticated;
```

Tilføj samme blok ordret i `db-migrations.sql` over `-- 5b-sektionen slutter her`, under overskriften `-- Trin 5b 2b-iii (#151): børnehenvisninger.` (`CREATE OR REPLACE` er idempotent).

- [ ] **Step 4: Kør testen igen, og se den bestå.** Genopbyg basen, så `schema.sql` er med.

Run: `bash $SCRATCH/mkdb.sh ci5b_child writer && env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d ci5b_child -f tests/sql/test-relation-child.sql`
Expected: `RELATION_CHILD_TEST_OK`.

- [ ] **Step 5: CI og commit.** Tilføj `test-relation-child` sidst i løkken i `.github/workflows/ci.yml` (linjen `for t in test-relation-persona-v2 … test-relation-person-create-v3; do`).

```bash
git add schema.sql db-migrations.sql tests/sql/test-relation-child.sql .github/workflows/ci.yml
git commit -m "feat(151): parser for bogens børnehenvisninger (2b-iii)"
```

---

### Task 2: Regelfunktionen og writer-grenen

**Files:**
- Modify: `schema.sql`:
  - `private.relation_child_rule` og `private.decide_relation_child` efter `relation_child_ref`;
  - i `red_afgoer_relation_interpretation` erstattes linjen med `RELATION_CHILD_DEFERRED` (grep);
  - regelrækkerne i blokken `-- Trin 5b 2a (#151): strukturelle familiebindinger.`
- Modify: `db-migrations.sql`: blokken fra Task 1 får begge nye funktioner, en **fuld kopi** af den ændrede `red_afgoer_relation_interpretation` og regelrækkerne idempotent.
- Modify: `tests/sql/test-relation-decision.sql`, linje 31-41: forventningen `RELATION_CHILD_DEFERRED` erstattes.
- Modify: `tests/sql/test-relation-child.sql`: regel- og writerdelen.

**Interfaces:**
- Consumes: `private.relation_child_ref(text)` (Task 1).
- Produces:
  - `private.relation_child_rule(p_interpretation_id uuid) RETURNS jsonb`. Resultatet er `{ok:bool, brud:text[], afvigelser:text[], ref:jsonb, principal_person_id:bigint, linje:text, family_id:bigint, children:[{person_id,konfidens,koen,linje,nr,kuld,gen_local,gen_through}], flock_digest:text}`, eller NULL for andre prædikater.
  - `private.decide_relation_child(p_ic private.interpretation, p_expected_version int, p_action text, p_family_id bigint, p_note text, p_ctx jsonb, p_basis text) RETURNS integer`.
  - Regelrækken `relation-child-v1`.
  - Afgørelsens evidens har nøglerne `method='relation-child-v1'`, `family_id`, `flock_digest`, `ref`, `afvigelser`, `sheet_sha256`, `rows_sha256` og `line`.

- [ ] **Step 1: Skriv de fejlende tests.** Opret `tests/sql/fixtures/relation-child.sql` med de tre hjælpere nedenfor. De er `pg_temp`-funktioner, så hver transaktion i testfilen starter med `BEGIN;`, `\ir fixtures/relation-5b.sql` og `\ir fixtures/relation-child.sql`.

`tests/sql/fixtures/relation-child.sql`:

```sql
-- Forælder -5701 med post V-1 og børn -5702..-5704 med egne poster V-2..V-4 (kuld V, lokalt slægtled 2).
CREATE OR REPLACE FUNCTION pg_temp.fc_setup(p_raw text,p_actor uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE s jsonb; pa jsonb; c jsonb; v_fam bigint; i int;
BEGIN
  INSERT INTO person(id,levende,privat,status,koen) VALUES (-5701,false,false,'2b3','mand'),(-5705,false,false,'2b3','kvinde');
  INSERT INTO person(id,levende,privat,status,koen) SELECT -5700-g,false,false,'2b3','mand' FROM generate_series(2,4) g;
  s:=pg_temp.f5b_source(-5701);
  pa:=pg_temp.f5b_post(-5701,s,'V-1','Ole Alfa. '||p_raw,ARRAY['Ole Alfa.',p_raw],-5701,p_actor);
  INSERT INTO person_external_id(person_id,source_id,linje,nr,record_key,kuld,slaegtled_lokal)
    VALUES (-5701,-5701,'V',1,'V-1','V',1);
  FOR i IN 2..4 LOOP
    PERFORM pg_temp.f5b_post(-5701,s,'V-'||i,'Barn '||i||' Alfa.',ARRAY['Barn '||i||' Alfa.'],-5700-i,p_actor);
    INSERT INTO person_external_id(person_id,source_id,linje,nr,record_key,kuld,slaegtled_lokal)
      VALUES (-5700-i,-5701,'V',i,'V-'||i,'V',2);
  END LOOP;
  v_fam:=pg_temp.f5b_family(-5701,-5705,1);
  INSERT INTO family_member(family_id,person_id,rolle) SELECT v_fam,-5700-g,'barn' FROM generate_series(2,4) g;
  c:=pg_temp.f5b_claim(-5701,s,'relation.child',(pa->'clauses'->>1)::uuid,p_raw);
  INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,post_offset,origin,origin_ref)
    VALUES ((c->>'key')::uuid,'principal',1,(pa->>'principal')::uuid,0,'relation_persona',gen_random_uuid());
  RETURN jsonb_build_object('claim',c,'family',v_fam,'source',s,'post',pa);
END $$;

-- Arkets kontekst (human_sheet) for linje 1.
CREATE OR REPLACE FUNCTION pg_temp.fc_ctx() RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('basis','human_sheet','sheet_sha256',repeat('a',64),'rows_sha256',repeat('b',64),'line',1) $$;

-- Kører red_afgoer_relation_interpretation som redaktion og returnerer fejlkoden eller 'OK'.
CREATE OR REPLACE FUNCTION pg_temp.fc_decide(p_key uuid,p_ver int,p_action text,p_fam bigint,p_ctx jsonb,p_actor uuid)
RETURNS text LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
  SET LOCAL ROLE authenticated;
  PERFORM red_afgoer_relation_interpretation(p_key,p_ver,p_action,p_fam,'test',p_ctx);
  RESET ROLE;
  RETURN 'OK';
EXCEPTION WHEN OTHERS THEN
  RESET ROLE;
  RETURN split_part(SQLERRM,':',1);
END $$;
```

Tilføj til `tests/sql/test-relation-child.sql` før `\echo RELATION_CHILD_TEST_OK`:

```sql
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-child.sql
DO $child_rule$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000002b3001'; f jsonb; k uuid; r jsonb; v_id uuid;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  f:=pg_temp.fc_setup('3 sønner: Andet slægtled, V, nr. 2-4',v_actor);
  k:=(f->'claim'->>'key')::uuid; v_id:=(f->'claim'->>'id')::uuid;
  r:=private.relation_child_rule(v_id);
  IF NOT (r->>'ok')::boolean OR (r->>'family_id')::bigint<>(f->>'family')::bigint OR jsonb_array_length(r->'afvigelser')<>0
     OR r->>'flock_digest' !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: lykkelig regel %',r; END IF;
  -- writer: p_family_id sat ⇒ afvist; unresolved ⇒ afvist; web_detail ⇒ afvist
  IF pg_temp.fc_decide(k,1,'same',(f->>'family')::bigint,pg_temp.fc_ctx(),v_actor)<>'RELATION_DECISION_INVALID'
     OR pg_temp.fc_decide(k,1,'unresolved',NULL,pg_temp.fc_ctx(),v_actor)<>'RELATION_DECISION_INVALID'
     OR pg_temp.fc_decide(k,1,'same',NULL,'{}'::jsonb,v_actor)<>'RELATION_DECISION_INVALID' THEN
    RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: writer-validering'; END IF;
  -- same ⇒ accepted, evidens med familie og digest, ingen child-part
  IF pg_temp.fc_decide(k,1,'same',NULL,pg_temp.fc_ctx(),v_actor)<>'OK' THEN RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: same'; END IF;
  IF (SELECT status FROM private.interpretation_current WHERE interpretation_key=k)<>'accepted'
     OR (SELECT decision_evidence->>'method' FROM private.interpretation_current WHERE interpretation_key=k)<>'relation-child-v1'
     OR (SELECT (decision_evidence->>'family_id')::bigint FROM private.interpretation_current WHERE interpretation_key=k)<>(f->>'family')::bigint
     OR EXISTS (SELECT 1 FROM private.interpretation_party WHERE interpretation_key=k AND party_role='child') THEN
    RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: evidens'; END IF;
END $child_rule$;
ROLLBACK;
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-child.sql
DO $child_breaks$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000002b3001'; f jsonb; v_id uuid; r jsonb;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  -- H5_nr: interval passer ikke (2-5 mod børn 2-4); A2 følger med
  f:=pg_temp.fc_setup('4 sønner: Andet slægtled, V, nr. 2-5',v_actor); v_id:=(f->'claim'->>'id')::uuid;
  r:=private.relation_child_rule(v_id);
  IF (r->>'ok')::boolean OR NOT (r->'brud') ? 'H5_nr' THEN RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: H5_nr %',r; END IF;
  IF pg_temp.fc_decide((f->'claim'->>'key')::uuid,1,'same',NULL,pg_temp.fc_ctx(),v_actor)<>'RELATION_CHILD_RULE_NOT_MET' THEN
    RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: writer håndhæver ikke H5'; END IF;
  -- rejected virker trods brud
  IF pg_temp.fc_decide((f->'claim'->>'key')::uuid,1,'rejected',NULL,pg_temp.fc_ctx(),v_actor)<>'OK' THEN
    RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: rejected'; END IF;
END $child_breaks$;
ROLLBACK;
```

Tilføj desuden én transaktion pr. brud med samme mønster (setup, `relation_child_rule`, forventet kode i `brud`):

| Brud | Opsætning | Forventet kode i `brud` |
| --- | --- | --- |
| Køn | raw `'3 døtre: Andet slægtled, V, nr. 2-4'` | `H4` |
| Romertal | raw `'3 sønner: Andet slægtled, III, nr. 2-4'` | `H5_romertal` |
| Slægtled | raw `'3 sønner: Tredje slægtled, V, nr. 2-4'` | `H5_slaegtled` |
| `omstridt` | lykkelig raw + `UPDATE family_member SET konfidens='omstridt' WHERE person_id=-5702` | `H3_raekker` |
| To familier | lykkelig raw + `PERFORM pg_temp.f5b_family(-5701,NULL,2); INSERT INTO family_member(family_id,person_id,rolle) VALUES (<ny>,-5706,'barn')` (person -5706 indsættes først) | `H3_familie` |
| Enkelt nummer | raw `'Søn: Andet slægtled, V, nr. 2'` | `H5_nr`, fordi børnene er 2-4 |
| Uden henvisning | raw `'3 sønner (?)'` | `ok=true`, `afvigelser` = `["A3_usikker","A4_uden_henvisning"]` |
| Antal | raw `'4 sønner: Andet slægtled, V, nr. 2-4'` | `ok=true`, `afvigelser` ⊇ `A1_antal_familie`, `A2_antal_interval` |

Ret `tests/sql/test-relation-decision.sql` linje 31-41: de to blokke forventer nu `RELATION_DECISION_INVALID` i stedet for `RELATION_CHILD_DEFERRED`. Kaldene sender `v_fam` (same), og `'{}'` er ikke `human_sheet` (unresolved). Kommentaren ændres til »2b-iii: et barn afgøres kun via arket og uden familie-id«.

- [ ] **Step 2: Kør testene, og se dem fejle.**

Run: `bash $SCRATCH/mkdb.sh ci5b_child writer && for t in test-relation-child test-relation-decision; do env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d ci5b_child -f tests/sql/$t.sql || echo FEJL $t; done`
Expected: `FEJL test-relation-child` (`private.relation_child_rule` findes ikke) og `FEJL test-relation-decision` (`RELATION_CHILD_DEFERRED` kastes stadig).

- [ ] **Step 3: Implementér i `schema.sql`.** Først regelfunktionen, efter `relation_child_ref`:

```sql
-- Trin 5b 2b-iii (spec §5): reglen relation-child-v1 mod familien, som den ser ud nu. Bruges af writeren (§6),
-- bindingstilstanden (§7) og arkets projektion (§6). H = brud (kan ikke tilsidesættes), A = afvigelser (mennesket kan).
CREATE OR REPLACE FUNCTION private.relation_child_rule(p_interpretation_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE
  v_i private.interpretation%ROWTYPE; v_ref jsonb; v_pid bigint; v_linje text; v_n integer; v_fams bigint[];
  v_f bigint; v_kids jsonb; v_h text[]:='{}'; v_a text[]:='{}'; v_from integer; v_to integer;
BEGIN
  SELECT * INTO v_i FROM private.interpretation WHERE id=p_interpretation_id;
  IF NOT FOUND OR v_i.predicate<>'relation.child' THEN RETURN NULL; END IF;
  -- H1: én klausul; hovedperson med accepteret identitet og præcis én postnøgle (linje sat) i kilden
  IF (SELECT count(*) FROM private.interpretation_observation io
       WHERE io.interpretation_id=v_i.id AND io.evidence_role='supporting')<>1 THEN v_h:=v_h||'H1_klausul'::text; END IF;
  SELECT i.canonical_person_id INTO v_pid FROM private.interpretation_party_current pc
    JOIN private.source_persona_identity i ON i.source_persona_id=pc.source_persona_id AND i.decision_status='accepted'
   WHERE pc.interpretation_key=v_i.interpretation_key AND pc.party_role='principal';
  IF v_pid IS NULL THEN
    v_h:=v_h||'H1_hovedperson'::text;
  ELSE
    SELECT min(x.linje),count(*) INTO v_linje,v_n FROM public.person_external_id x
     WHERE x.person_id=v_pid AND x.source_id=v_i.source_id;
    IF v_n<>1 OR v_linje IS NULL THEN v_h:=v_h||'H1_postnoegle'::text; END IF;
    -- H3: præcis én partnerfamilie med børn
    SELECT array_agg(DISTINCT p.family_id ORDER BY p.family_id) INTO v_fams FROM public.family_member p
     WHERE p.person_id=v_pid AND p.rolle='partner'
       AND EXISTS (SELECT 1 FROM public.family_member b WHERE b.family_id=p.family_id AND b.rolle='barn');
  END IF;
  v_ref:=private.relation_child_ref(v_i.value->>'raw');
  IF v_ref IS NULL THEN v_h:=v_h||'H2'::text; END IF;
  IF coalesce(cardinality(v_fams),0)<>1 THEN
    v_h:=v_h||'H3_familie'::text;
  ELSE
    v_f:=v_fams[1];
    IF EXISTS (SELECT 1 FROM public.family_member m WHERE m.family_id=v_f
                AND (m.konfidens='omstridt' OR m.rolle IN ('adopteret_barn','plejebarn','stedbarn'))) THEN
      v_h:=v_h||'H3_raekker'::text;
    END IF;
    SELECT coalesce(jsonb_agg(jsonb_build_object('person_id',b.person_id,'konfidens',b.konfidens,'koen',pp.koen,
             'linje',x.linje,'nr',x.nr,'kuld',x.kuld,'gen_local',x.slaegtled_lokal,'gen_through',x.slaegtled_gennem)
             ORDER BY b.person_id),'[]'::jsonb)
      INTO v_kids
      FROM public.family_member b
      JOIN public.person pp ON pp.id=b.person_id
      LEFT JOIN public.person_external_id x ON x.person_id=b.person_id AND x.source_id=v_i.source_id
     WHERE b.family_id=v_f AND b.rolle='barn';
    IF v_ref IS NOT NULL THEN
      -- H4: køn
      IF v_ref->>'sex' IS NOT NULL AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_kids) k
                                                WHERE k->>'koen' IS DISTINCT FROM v_ref->>'sex') THEN
        v_h:=v_h||'H4'::text;
      END IF;
      IF v_ref->>'nr_from' IS NOT NULL THEN
        v_from:=(v_ref->>'nr_from')::integer; v_to:=(v_ref->>'nr_to')::integer;
        -- H5: numrene i forælderens linje = intervallet; ingen børn med post i en anden linje; romertal; slægtled
        IF (SELECT array_agg((k->>'nr')::integer ORDER BY (k->>'nr')::integer) FROM jsonb_array_elements(v_kids) k
             WHERE k->>'linje' IS NOT DISTINCT FROM v_linje)
           IS DISTINCT FROM (SELECT array_agg(g ORDER BY g) FROM generate_series(v_from,v_to) g) THEN
          v_h:=v_h||'H5_nr'::text;
        END IF;
        IF EXISTS (SELECT 1 FROM jsonb_array_elements(v_kids) k
                    WHERE k->>'linje' IS NOT NULL AND k->>'linje' IS DISTINCT FROM v_linje) THEN
          v_h:=v_h||'H5_linje'::text;
        END IF;
        IF v_ref->>'section' IS NOT NULL AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_kids) k
             WHERE k->>'linje' IS NOT NULL AND v_ref->>'section' IS DISTINCT FROM k->>'linje'
               AND v_ref->>'section' IS DISTINCT FROM k->>'kuld') THEN
          v_h:=v_h||'H5_romertal'::text;
        END IF;
        IF v_ref->>'gen_local' IS NOT NULL AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_kids) k
             WHERE k->>'linje' IS NOT NULL AND k->>'gen_local' IS DISTINCT FROM v_ref->>'gen_local') THEN
          v_h:=v_h||'H5_slaegtled'::text;
        END IF;
        IF v_ref->>'gen_through' IS NOT NULL AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_kids) k
             WHERE k->>'linje' IS NOT NULL AND k->>'gen_through' IS DISTINCT FROM v_ref->>'gen_through') THEN
          v_h:=v_h||'H5_slaegtled_gennem'::text;
        END IF;
      ELSIF NOT EXISTS (SELECT 1 FROM jsonb_array_elements(v_kids) k WHERE k->>'linje' IS NOT NULL) THEN
        v_h:=v_h||'H6'::text;   -- uden henvisning: mindst ét barn med egen post
      END IF;
      -- A: afvigelser, som mennesket kan tilsidesætte
      IF (v_ref->>'count')::integer IS DISTINCT FROM jsonb_array_length(v_kids) THEN v_a:=v_a||'A1_antal_familie'::text; END IF;
      IF v_from IS NOT NULL AND (v_ref->>'count')::integer IS DISTINCT FROM v_to-v_from+1 THEN v_a:=v_a||'A2_antal_interval'::text; END IF;
      IF (v_ref->>'uncertain')::boolean THEN v_a:=v_a||'A3_usikker'::text; END IF;
      IF v_from IS NULL THEN v_a:=v_a||'A4_uden_henvisning'::text; END IF;
    END IF;
  END IF;
  RETURN jsonb_build_object('ok',cardinality(v_h)=0,'brud',to_jsonb(v_h),'afvigelser',to_jsonb(v_a),'ref',v_ref,
    'principal_person_id',v_pid,'linje',v_linje,'family_id',v_f,'children',coalesce(v_kids,'[]'::jsonb),
    'flock_digest',CASE WHEN v_kids IS NOT NULL THEN private.reimport_canonical_json_sha256(coalesce((
        SELECT jsonb_agg(jsonb_build_object('person_id',k->'person_id','rolle','barn','konfidens',k->'konfidens')
                         ORDER BY (k->>'person_id')::bigint) FROM jsonb_array_elements(v_kids) k),'[]'::jsonb)) END);
END $$;
REVOKE ALL ON FUNCTION private.relation_child_rule(uuid) FROM PUBLIC,anon,authenticated;
```

Derefter afgørelsen:

```sql
-- Trin 5b 2b-iii (spec §6): børnegrenen af red_afgoer_relation_interpretation. Kun arket (human_sheet); serveren
-- udleder familien; ingen child-part; unresolved afvises, fordi en afgjort fortolkning ikke kan genåbnes.
CREATE OR REPLACE FUNCTION private.decide_relation_child(p_ic private.interpretation,p_expected_version integer,
  p_action text,p_family_id bigint,p_note text,p_ctx jsonb,p_basis text)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
DECLARE v_rule jsonb; v_evidence jsonb; v_new uuid; v_pid bigint;
BEGIN
  IF p_basis IS DISTINCT FROM 'human_sheet' OR p_ctx ? 'control_run_id' OR p_family_id IS NOT NULL
     OR p_action NOT IN ('same','rejected') THEN
    RAISE EXCEPTION 'RELATION_DECISION_INVALID';
  END IF;
  v_evidence:=jsonb_build_object('note',btrim(p_note),'action',p_action,'basis',p_basis,'method','relation-child-v1',
    'sheet_sha256',p_ctx->>'sheet_sha256','rows_sha256',p_ctx->>'rows_sha256','line',(p_ctx->>'line')::integer);
  IF p_action='same' THEN
    SELECT i.canonical_person_id INTO v_pid FROM private.interpretation_party_current pc
      JOIN private.source_persona_identity i ON i.source_persona_id=pc.source_persona_id AND i.decision_status='accepted'
     WHERE pc.interpretation_key=p_ic.interpretation_key AND pc.party_role='principal';
    -- Rækkelåse (personer → familier → medlemmer) før den endelige genberegning af reglen.
    IF v_pid IS NOT NULL THEN PERFORM private.lock_family_rows(ARRAY[v_pid]); END IF;
    v_rule:=private.relation_child_rule(p_ic.id);
    IF v_rule IS NULL OR NOT coalesce((v_rule->>'ok')::boolean,false) THEN
      RAISE EXCEPTION 'RELATION_CHILD_RULE_NOT_MET: %',coalesce(v_rule->>'brud','[]');
    END IF;
    v_evidence:=v_evidence||jsonb_build_object('family_id',(v_rule->>'family_id')::bigint,
      'flock_digest',v_rule->>'flock_digest','ref',v_rule->'ref','afvigelser',v_rule->'afvigelser');
    v_new:=public.red_decide_interpretation(p_ic.id,p_expected_version,'accepted',v_evidence);
  ELSE
    v_new:=public.red_decide_interpretation(p_ic.id,p_expected_version,'rejected',v_evidence);
  END IF;
  RETURN (SELECT version FROM private.interpretation WHERE id=v_new);
END $$;
REVOKE ALL ON FUNCTION private.decide_relation_child(private.interpretation,integer,text,bigint,text,jsonb,text) FROM PUBLIC,anon,authenticated;
```

I `red_afgoer_relation_interpretation` slettes de to kommentarlinjer og linjen

```sql
  IF v_ic.predicate='relation.child' THEN RAISE EXCEPTION 'RELATION_CHILD_DEFERRED'; END IF;
```

Derefter indsættes umiddelbart **efter** linjen `PERFORM pg_advisory_xact_lock_shared(hashtextextended('daa-identity-candidates:'||v_ic.source_id::text,0));`, så børn og forældre tager samme kildelås:

```sql
  -- Trin 5b 2b-iii (spec 2026-10-20 §6): børnehenvisninger har deres egen gren (flokken binder til familien).
  IF v_ic.predicate='relation.child' THEN
    RETURN private.decide_relation_child(v_ic,p_expected_version,p_action,p_family_id,p_note,v_ctx,v_basis);
  END IF;
```

Funktionens øvrige krop er uændret.

Regelrækkerne: udvid de to `INSERT`-sætninger i blokken `-- Trin 5b 2a (#151): strukturelle familiebindinger.`. `interpretation_promotion_rule_line` får `('relation-child-v1','relation.child')`, og `interpretation_promotion_rule` får `('relation-child-v1',1,'relation.child','relation','family',NULL,'relation',false,false,true,'active','structural_family')`.

- [ ] **Step 4: Migrationer.** Blokken i `db-migrations.sql` fra Task 1 udvides med:
  - `private.relation_child_rule` og `private.decide_relation_child` ordret fra `schema.sql`;
  - en fuld kopi af den nye `red_afgoer_relation_interpretation` fra `schema.sql`, inkl. REVOKE og GRANT;
  - regelrækkerne idempotent:

```sql
INSERT INTO private.interpretation_promotion_rule_line(rule_key,predicate)
SELECT 'relation-child-v1','relation.child'
 WHERE NOT EXISTS (SELECT 1 FROM private.interpretation_promotion_rule_line WHERE rule_key='relation-child-v1');
INSERT INTO private.interpretation_promotion_rule(rule_key,rule_version,predicate,interpretation_kind,target_type,
  expected_fact_type,value_kind,requires_persona_identity,requires_principal_placement,bulk_eligible,status,rule_mode)
SELECT 'relation-child-v1',1,'relation.child','relation','family',NULL,'relation',false,false,true,'active','structural_family'
 WHERE NOT EXISTS (SELECT 1 FROM private.interpretation_promotion_rule WHERE rule_key='relation-child-v1' AND rule_version=1);
```

- [ ] **Step 5: Kør testene, og se dem bestå. Kør også migrationsstien.**

Run: `bash $SCRATCH/mkdb.sh ci5b_child writer && for t in test-relation-child test-relation-decision test-relation-binding test-family-sources; do env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d ci5b_child -f tests/sql/$t.sql >/dev/null && echo OK $t || echo FEJL $t; done`
Expected: `OK` for alle fire.

Migrationsstien (mønster: runde 2's `t3m.sh`):
1. Byg en base fra `git show origin/main:schema.sql` og `db-rls.sql` plus writer-bootstraps.
2. Kør HEAD's `db-migrations.sql` to gange.
3. Kør `db-rls.sql`.
4. Kør `test-relation-child` og `test-relation-decision`.

Expected: begge `OK`, og anden kørsel af migrationerne giver rc 0.

- [ ] **Step 6: Commit.**

```bash
git add schema.sql db-migrations.sql tests/sql/test-relation-child.sql tests/sql/fixtures/relation-child.sql tests/sql/test-relation-decision.sql
git commit -m "feat(151): regel relation-child-v1 og writer-gren for børnehenvisninger"
```

---

### Task 3: Bindingstilstand og læserens kilde

**Files:**
- Modify: `schema.sql`: `private.relation_binding_state` (børnegren først) og `public.public_family_sources` (`slags`-CASE).
- Modify: `db-migrations.sql`: fulde kopier af begge funktioner i 2b-iii-blokken.
- Modify: `tests/sql/test-relation-child.sql`: binding, drift og anon-visning.

**Interfaces:**
- Consumes: `private.relation_child_rule`, afgørelsens evidens (`family_id`) og `relation-child-v1` (Task 2).
- Produces:
  - `relation_binding_state` for `relation.child` returnerer `{contract,interpretation,parties:[principal],family:{family_id,rows},counterpart_person_id:<forælder>,children:{count,section,nr_from,nr_to,sex},flock_digest}`, eller NULL.
  - `public_family_sources` giver `slags='boern'` med `counterpart_person_id` = forælderen.

- [ ] **Step 1: Skriv de fejlende tests.** Tilføj en transaktion til `test-relation-child.sql`. Den inkluderer `fixtures/relation-2a.sql` for `f2a_publish` og tester:
  - lykkelig binding og anon-visning;
  - barn uden post før binding;
  - barn med post uden for intervallet før binding;
  - barn efter binding med genbinding;
  - barn flyttet ud efter binding;
  - ikke-offentligt medlem.

```sql
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
\ir fixtures/relation-child.sql
CREATE OR REPLACE FUNCTION pg_temp.fc_bind(p_src bigint,p_iid uuid,p_fam bigint,p_actor uuid) RETURNS text LANGUAGE plpgsql AS $$
DECLARE items jsonb:=jsonb_build_array(jsonb_build_object('interpretation_id',p_iid::text,'family_id',p_fam)); pv jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_promotions(p_src,items);
  IF NOT (pv->'items'->0->>'eligible')::boolean THEN RESET ROLE; RETURN pv->'items'->0->>'reason_code'; END IF;
  PERFORM red_promote_relation_interpretations_batch(p_src,items,pv->>'preview_sha256');
  RESET ROLE;
  RETURN 'BOUND';
END $$;
CREATE OR REPLACE FUNCTION pg_temp.fc_boern(p_fam bigint) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE n integer;
BEGIN
  SET LOCAL ROLE anon;
  SELECT count(*) INTO n FROM public.public_family_sources(ARRAY[p_fam]) s WHERE s.slags='boern' AND s.counterpart_person_id=-5701;
  RESET ROLE;
  RETURN n;
END $$;
DO $child_bind$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000002b3001'; f jsonb; k uuid; v_fam bigint; v_iid uuid;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  f:=pg_temp.fc_setup('3 sønner: Andet slægtled, V, nr. 2-4',v_actor);
  k:=(f->'claim'->>'key')::uuid; v_fam:=(f->>'family')::bigint;
  PERFORM pg_temp.f2a_publish(-5701,f->'source',f->'post',-5701,v_actor,'Ole Alfa. 3 sønner: Andet slægtled, V, nr. 2-4');
  IF pg_temp.fc_decide(k,1,'same',NULL,pg_temp.fc_ctx(),v_actor)<>'OK' THEN RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: afgør'; END IF;
  -- Review Focus 2a: barn UDEN egen post tilføjet før binding ⇒ H holder, den aktuelle flok bindes
  INSERT INTO person(id,levende,privat,status,koen) VALUES (-5707,false,false,'2b3','mand');
  INSERT INTO family_member(family_id,person_id,rolle) VALUES (v_fam,-5707,'barn');
  SELECT id INTO v_iid FROM private.interpretation_current WHERE interpretation_key=k;
  IF pg_temp.fc_bind(-5701,v_iid,v_fam,v_actor)<>'BOUND' THEN RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: binding'; END IF;
  IF (private.relation_binding_state(v_iid)->>'counterpart_person_id')::bigint<>-5701
     OR pg_temp.fc_boern(v_fam)<>1 THEN RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: synlig boern-kilde'; END IF;
  -- barn tilføjet EFTER binding ⇒ ny tilstand ⇒ usynlig; genbinding bringer den tilbage (H holder)
  INSERT INTO person(id,levende,privat,status,koen) VALUES (-5708,false,false,'2b3','mand');
  INSERT INTO family_member(family_id,person_id,rolle) VALUES (v_fam,-5708,'barn');
  IF pg_temp.fc_boern(v_fam)<>0 THEN RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: drift ikke skjult'; END IF;
  IF pg_temp.fc_bind(-5701,v_iid,v_fam,v_actor)<>'BOUND' OR pg_temp.fc_boern(v_fam)<>1 THEN
    RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: genbinding'; END IF;
  -- barn med egen post flyttet ud ⇒ H5_nr ⇒ usynlig og genbinding afvist
  DELETE FROM family_member WHERE family_id=v_fam AND person_id=-5704;
  IF private.relation_binding_state(v_iid) IS NOT NULL OR pg_temp.fc_boern(v_fam)<>0
     OR pg_temp.fc_bind(-5701,v_iid,v_fam,v_actor)<>'RELATION_PROMOTION_STRUCTURE_INVALID' THEN
    RAISE EXCEPTION 'RELATION_CHILD_TEST_FAILED: flyttet barn'; END IF;
END $child_bind$;
ROLLBACK;
```

Tilføj to transaktioner med samme opsætning:
- **Barn med post uden for intervallet før binding.** Efter `fc_decide(...'same'...)` indsættes person -5709 med `person_external_id` (`linje 'V'`, `nr 9`, `kuld 'V'`, `slaegtled_lokal 2`) som `barn`. Forventet `fc_bind(...)` = `RELATION_PROMOTION_STRUCTURE_INVALID`.
- **Ikke-offentligt medlem (Review Focus 3).** Efter en lykkelig binding sættes `UPDATE person SET levende=true WHERE id=-5703`. Forventet `fc_boern(v_fam)` = 0.

- [ ] **Step 2: Kør testen, og se den fejle.**

Run: `bash $SCRATCH/mkdb.sh ci5b_child writer && env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d ci5b_child -f tests/sql/test-relation-child.sql`
Expected: FAIL `RELATION_CHILD_TEST_FAILED: binding`, fordi tilstanden er NULL for `relation.child`, og preview giver `RELATION_PROMOTION_STRUCTURE_INVALID`.

- [ ] **Step 3: Implementér.** I `private.relation_binding_state` erklæres `v_rule jsonb;` i DECLARE. Lige efter `SELECT * INTO v_i FROM private.interpretation WHERE id=p_interpretation_id;` og **før** linjen `IF NOT FOUND OR v_i.predicate NOT IN ('relation.marriage','relation.parent') THEN RETURN NULL; END IF;` indsættes:

```sql
  -- Trin 5b 2b-iii (spec §7): børneflokken bindes til familien; reglen genberegnes mod familien, som den ser ud nu.
  IF FOUND AND v_i.predicate='relation.child' THEN
    IF v_i.decision_evidence->>'method' IS DISTINCT FROM 'relation-child-v1' THEN RETURN NULL; END IF;
    v_rule:=private.relation_child_rule(v_i.id);
    IF v_rule IS NULL OR NOT coalesce((v_rule->>'ok')::boolean,false)
       OR (v_rule->>'family_id')::bigint IS DISTINCT FROM (v_i.decision_evidence->>'family_id')::bigint THEN
      RETURN NULL;
    END IF;
    SELECT jsonb_agg(jsonb_build_object('party_role',pc.party_role,'version',pc.version,
             'source_persona_id',pc.source_persona_id::text,'identity_version',i.version,
             'decision_status',i.decision_status,'canonical_person_id',i.canonical_person_id))
      INTO v_parties
      FROM private.interpretation_party_current pc
      LEFT JOIN private.source_persona_identity i ON i.source_persona_id=pc.source_persona_id
     WHERE pc.interpretation_key=v_i.interpretation_key AND pc.party_role='principal';
    SELECT jsonb_agg(jsonb_build_array(fm.person_id,fm.rolle,fm.ordinal,fm.konfidens) ORDER BY fm.person_id,fm.rolle COLLATE "C")
      INTO v_rows
      FROM public.family_member fm
     WHERE fm.family_id=(v_rule->>'family_id')::bigint
       AND ((fm.person_id=(v_rule->>'principal_person_id')::bigint AND fm.rolle='partner') OR fm.rolle='barn');
    RETURN jsonb_build_object('contract','relation-binding-state-v1',
      'interpretation',jsonb_build_object('interpretation_id',v_i.id::text,'interpretation_key',v_i.interpretation_key::text,
        'version',v_i.version,'status',v_i.status,'predicate',v_i.predicate,'source_id',v_i.source_id),
      'parties',v_parties,
      'family',jsonb_build_object('family_id',(v_rule->>'family_id')::bigint,'rows',v_rows),
      'counterpart_person_id',(v_rule->>'principal_person_id')::bigint,
      'children',jsonb_build_object('count',v_rule#>'{ref,count}','section',v_rule#>'{ref,section}',
        'nr_from',v_rule#>'{ref,nr_from}','nr_to',v_rule#>'{ref,nr_to}','sex',v_rule#>'{ref,sex}'),
      'flock_digest',v_rule->>'flock_digest');
  END IF;
```

I `public.public_family_sources` (grep `'aegteskab' ELSE 'foraelder'`) erstattes

```sql
CASE pub.predicate WHEN 'relation.marriage' THEN 'aegteskab' ELSE 'foraelder' END
```

med

```sql
CASE pub.predicate WHEN 'relation.marriage' THEN 'aegteskab' WHEN 'relation.parent' THEN 'foraelder' ELSE 'boern' END
```

Fulde kopier af begge funktioner kommer i 2b-iii-blokken i `db-migrations.sql`, ordret fra `schema.sql` inkl. REVOKE og GRANT.

- [ ] **Step 4: Kør testene, og se dem bestå.**

Run: `bash $SCRATCH/mkdb.sh ci5b_child writer && for t in test-relation-child test-relation-binding test-family-sources test-relation-decision; do env -u PGOPTIONS psql -X -q -v ON_ERROR_STOP=1 -d ci5b_child -f tests/sql/$t.sql >/dev/null && echo OK $t || echo FEJL $t; done`
Expected: `OK` for alle fire.

- [ ] **Step 5: Commit.**

```bash
git add schema.sql db-migrations.sql tests/sql/test-relation-child.sql
git commit -m "feat(151): børneflokken bindes til familien og vises som kilde (boern)"
```

---

### Task 4: Arket (projektion, Python og e2e)

**Files:**
- Modify: `schema.sql`, efter `private.decide_relation_child`: `private.relation_child_sheet_input(bigint)` og `public.red_relation_child_sheet_input(bigint)`.
- Modify: `db-migrations.sql` (kopi i blokken), `db-rls.sql`, `db-verify.sql` og `db-migrations.sql`'s `to_regprocedure`-liste. Tilføj `public.red_relation_child_sheet_input(bigint)` lige under `public.red_relation_persona_v3_input(bigint)` i alle tre lister.
- Create:
  - `.claude/skills/daa-extract/scripts/relation_child_rows.sql`;
  - `.claude/skills/daa-extract/scripts/relation_child_sheet.py`;
  - `.claude/skills/daa-extract/scripts/test_relation_child_sheet.py`;
  - `tests/sql/fixtures/relation-child-e2e.sql`;
  - `tests/sql/test-relation-child-sheet.sh`.
- Modify: `.github/workflows/ci.yml`:
  - pytest-linjen (step med `test_relation_marriage_sheet_v3.py`) får `test_relation_child_sheet.py`;
  - e2e-steppet »Ægteskabsark ende til ende (5b 2b-ii)« får `bash tests/sql/test-relation-child-sheet.sh ci5b_2bii_sheet`.

**Interfaces:**
- Consumes: `private.relation_child_rule` (Task 2) og `red_afgoer_relation_interpretation` (Task 2).
- Produces:
  - Kontrakten `relation-child-sheet-input-v1`: `{contract, source_id, rows:[{row_no, interpretation_key, interpretation_version, raw, rule:{…relation_child_rule…}, children_named:[{person_id,navn,foedt,linje,nr,kuld,gen_local}]}]}`. `rows` er sorteret efter `interpretation_key`, og `row_no` er 1-baseret.
  - CLI: `relation_child_sheet.py render --rows R --out O` udskriver `ARK_OK passer=<n> kort=<n> uden=<n>`. `relation_child_sheet.py sql --rows R --sheet S --approved-sha256 H --expect-rows-sha256 H --decision-out D` udskriver `SQL_OK b=<n> r=<n> u=<n>`.

- [ ] **Step 1: Skriv de fejlende pytest-tests** i `test_relation_child_sheet.py`, med opdigtede navne:

```python
"""Trin 5b 2b-iii (spec §6): børnearket. Kun opdigtede navne."""
import pytest

import relation_child_sheet as cs
from decision_sheet_core import SheetError

K1, K2, K3 = ("00000000-0000-0000-0000-00000000000" + c for c in "123")


def row(no, key, ok=True, afv=(), brud=()):
    return {"row_no": no, "interpretation_key": key, "interpretation_version": 1, "raw": "3 sønner: Andet slægtled, V, nr. 2-4",
            "rule": {"ok": ok, "brud": list(brud), "afvigelser": list(afv), "family_id": 7},
            "children_named": [{"person_id": 1, "navn": "Ib Alfa", "foedt": "1801", "linje": "V", "nr": 2, "kuld": "V", "gen_local": 2}]}


ROWS = {"contract": "relation-child-sheet-input-v1", "source_id": 1,
        "rows": [row(1, K1), row(2, K2, afv=["A3_usikker"]), row(3, K3, ok=False, brud=["H3_familie"])]}


def test_render_blokke_og_forudfyldning():
    t = cs.render_sheet(ROWS)
    assert f"C {K1} 1 : B" in t and f"C {K2} 1 : B" in t and K3 not in t
    assert t.index(K1) < t.index("# Kort") < t.index(K2)
    assert "Ikke på arket: 1" in t


def test_beslutnings_sql_b_r_u():
    t = cs.render_sheet(ROWS).replace(f"C {K2} 1 : B", f"C {K2} 1 : R")
    sql = cs.decision_sql(cs.parse_sheet(t), ROWS, sheet_sha256="a" * 64, rows_sha256="b" * 64)
    assert sql.count("red_afgoer_relation_interpretation(") == 2
    assert f"'{K1}'::uuid, 1, 'same', NULL" in sql and f"'{K2}'::uuid, 1, 'rejected', NULL" in sql
    assert '"line": 1' in sql and '"basis": "human_sheet"' in sql
    t_u = t.replace(f"C {K1} 1 : B", f"C {K1} 1 : U")
    assert cs.decision_sql(cs.parse_sheet(t_u), ROWS, sheet_sha256="a" * 64, rows_sha256="b" * 64).count("red_afgoer_relation_interpretation(") == 1


@pytest.mark.parametrize("edit,code", [
    (lambda t: t.replace(f"C {K1} 1 : B", f"C {K1} 1 : S"), "SHEET_TOKEN_NOT_ALLOWED"),
    (lambda t: t + f"C {K3} 1 : B\n", "SHEET_LINE_UNKNOWN"),                 # Review Focus 4: H-brud på arket
    (lambda t: t.replace(f"C {K1} 1 : B\n", ""), "SHEET_LINES_MISSING"),
    (lambda t: t + f"C {K1} 1 : B\n", "SHEET_LINE_DUPLICATE"),
    (lambda t: t.replace(f"C {K1} 1 : B", f"C {K1} 2 : B"), "SHEET_LINE_UNKNOWN"),
])
def test_ark_fejl(edit, code):
    with pytest.raises(SheetError, match=code):
        cs.decision_sql(cs.parse_sheet(edit(cs.render_sheet(ROWS))), ROWS, sheet_sha256="a" * 64, rows_sha256="b" * 64)
```

- [ ] **Step 2: Kør testen, og se den fejle.**

Run: `$SCRATCH/venv314/bin/python -m pytest -q .claude/skills/daa-extract/scripts/test_relation_child_sheet.py`
Expected: FAIL med `ModuleNotFoundError: No module named 'relation_child_sheet'`.

- [ ] **Step 3: Implementér `relation_child_sheet.py`:**

```python
"""Trin 5b 2b-iii (spec §6): børnearket — ét hash-bundet ark for alle børnehenvisninger, der opfylder H.

Rækkefil og ark rummer navne og bogens tekst; værktøjet printer kun antal og koder. `sql` laver ét afgørelsesscript
(red_afgoer_relation_interpretation med human_sheet-kontekst). Serveren genberegner reglen og afviser H-brud.
"""
from __future__ import annotations

import argparse
import json
import re
from dataclasses import dataclass
from pathlib import Path

from decision_sheet_core import SheetError, require_hex64, sql_literal, verify_bound
from spouse_exception_sheet import _write_private, check_private_path

CONTRACT = "relation-child-sheet-input-v1"
UUID = r"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"
C_RE = re.compile(rf"^C (?P<key>{UUID}) (?P<ver>[0-9]+) : (?P<tok>\S+)\s*(?:#\s*(?P<note>.*))?$")
LOOSE_RE = re.compile(rf"^C {UUID} ")
TOKENS = {"B", "R", "U"}


@dataclass
class Line:
    key: str
    version: int
    tok: str
    note: str | None


def _ok_rows(rows: dict) -> dict[str, dict]:
    if rows.get("contract") != CONTRACT:
        raise SheetError("ROWS_CONTRACT_INVALID")
    return {r["interpretation_key"]: r for r in rows["rows"] if r["rule"].get("ok")}


def _child(c: dict) -> str:
    return f"#     {c['navn']} (f. {c.get('foedt') or '?'}) [{c.get('linje') or '-'}-{c.get('nr') or '-'}, kuld {c.get('kuld') or '-'}, slægtled {c.get('gen_local') or '-'}]"


def render_sheet(rows: dict) -> str:
    ok = _ok_rows(rows)
    passer = [r for r in ok.values() if not r["rule"]["afvigelser"]]
    kort = [r for r in ok.values() if r["rule"]["afvigelser"]]
    uden = [r for r in rows["rows"] if not r["rule"].get("ok")]
    out = ["# Børnearket (2b-iii). Tokens: B = bind, R = afvis påstanden, U = lad stå (intet skrives).",
           "# Passer helt (alle krav og ingen afvigelser) — forudfyldt B:"]
    for r in sorted(passer, key=lambda r: r["row_no"]):
        out.append(f"#   »{r['raw']}« — {len(r['children_named'])} børn")
        out.append(f"C {r['interpretation_key']} {r['interpretation_version']} : B")
    out.append("# Kort (afvigelser, som du kan tilsidesætte) — forudfyldt B:")
    for r in sorted(kort, key=lambda r: r["row_no"]):
        out.append(f"#   »{r['raw']}« — afvigelser: {', '.join(r['rule']['afvigelser'])}")
        out.extend(_child(c) for c in r["children_named"])
        out.append(f"C {r['interpretation_key']} {r['interpretation_version']} : B")
    brud = sorted({b for r in uden for b in r["rule"].get("brud", [])})
    out.append(f"# Ikke på arket: {len(uden)} (brud: {', '.join(brud) or '-'})")
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
        if r is None or r["interpretation_version"] != l.version:
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
    todo = [(l, r) for l, r in check_sheet(lines, rows) if l.tok in ("B", "R")]
    sql = ["\\set ON_ERROR_STOP on", "BEGIN;", "SET LOCAL standard_conforming_strings=on;", "SET LOCAL TimeZone='UTC';",
           "SET LOCAL search_path=pg_catalog,public,private;",
           "SELECT set_config('request.jwt.claim.sub', :'actor', true) IS NOT NULL AS ok \\g /dev/null",
           "SET LOCAL ROLE authenticated;"]
    tag = sheet_sha256[:12]
    for l, r in todo:
        ctx = {"basis": "human_sheet", "sheet_sha256": sheet_sha256, "rows_sha256": rows_sha256, "line": r["row_no"]}
        note = sql_literal(f"børneark {tag} række {r['row_no']}" + (f" — {l.note}" if l.note else ""))
        action = "same" if l.tok == "B" else "rejected"
        sql.append(f"SELECT red_afgoer_relation_interpretation('{l.key}'::uuid, {l.version}, '{action}', NULL, {note}, "
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
            kort = sum(1 for x in ok.values() if x["rule"]["afvigelser"])
            print(f"ARK_OK passer={len(ok) - kort} kort={kort} uden={len(rows['rows']) - len(ok)}")
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
    print(f"SQL_OK b={toks.count('B')} r={toks.count('R')} u={toks.count('U')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
```

- [ ] **Step 4: Kør pytest, og se den bestå.**

Run: `$SCRATCH/venv314/bin/python -m pytest -q .claude/skills/daa-extract/scripts/test_relation_child_sheet.py`
Expected: `7 passed`.

- [ ] **Step 5: Projektionen i `schema.sql`.** Mønster: `relation_persona_v3_input` og wrapperen.

```sql
-- Trin 5b 2b-iii (spec §6): arkets input. Kun ejeren lokalt mod restore-kopien; navne forlader aldrig den private mappe.
CREATE OR REPLACE FUNCTION private.relation_child_sheet_input(p_source_id bigint)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
  SELECT jsonb_build_object('contract','relation-child-sheet-input-v1','source_id',p_source_id,'rows',coalesce(jsonb_agg(
    jsonb_build_object('row_no',x.row_no,'interpretation_key',x.k,'interpretation_version',x.ver,'raw',x.raw,'rule',x.rule,
      'children_named',coalesce((SELECT jsonb_agg(jsonb_build_object('person_id',c->'person_id','navn',p.visning_navn,
          'foedt',p.visning_foedt,'linje',c->'linje','nr',c->'nr','kuld',c->'kuld','gen_local',c->'gen_local')
          ORDER BY (c->>'nr')::integer NULLS LAST,(c->>'person_id')::bigint)
        FROM jsonb_array_elements(x.rule->'children') c JOIN public.person p ON p.id=(c->>'person_id')::bigint),'[]'::jsonb))
    ORDER BY x.row_no),'[]'::jsonb))
  FROM (SELECT row_number() OVER (ORDER BY ic.interpretation_key::text COLLATE "C") AS row_no,
               ic.interpretation_key::text AS k,ic.version AS ver,ic.value->>'raw' AS raw,private.relation_child_rule(ic.id) AS rule
          FROM private.interpretation_current ic
         WHERE ic.source_id=p_source_id AND ic.predicate='relation.child' AND ic.status='proposed') x;
$$;
REVOKE ALL ON FUNCTION private.relation_child_sheet_input(bigint) FROM PUBLIC,anon,authenticated,service_role;
CREATE OR REPLACE FUNCTION public.red_relation_child_sheet_input(p_source_id bigint)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
BEGIN
  IF auth.uid() IS NULL OR public.current_rolle()<>'redaktion' THEN RAISE EXCEPTION 'EVIDENCE_ROLE_FORBIDDEN'; END IF;
  RETURN private.relation_child_sheet_input(p_source_id);
END $$;
REVOKE ALL ON FUNCTION public.red_relation_child_sheet_input(bigint) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION public.red_relation_child_sheet_input(bigint) TO authenticated;
```

Bemærk:
- `row_no` er rækkenummeret i den aktuelle projektion. Kun `proposed`-påstande tælles med, så nummeret er arkets »line«.
- Kopiér funktionerne til `db-migrations.sql`.
- Tilføj wrapperen i de tre ACL-lister: `db-rls.sql` ~703, `db-verify.sql` ~2981 og `db-migrations.sql` ~18827.

`relation_child_rows.sql` er en kopi af `relation_v3_rows.sql`, hvor kaldet er udskiftet til `public.red_relation_child_sheet_input(:source)` (samme `actor`/`source`-variabler og samme `\gset`-mønster).

- [ ] **Step 6: E2e i en engangsbase.**

`tests/sql/fixtures/relation-child-e2e.sql` bygger kilde -22701:
- én forælder med to henvisninger, hvor den ene passer helt og den anden er »3 sønner (?)«;
- én hovedperson med to familier (H3).

Byg den med de rå `INSERT`-mønstre fra `tests/sql/fixtures/relation-marriage-v3.sql`, inklusive `person_external_id` og `koen`.

`tests/sql/test-relation-child-sheet.sh` følger `test-relation-marriage-sheet-v3.sh`:
1. Render og forvent `ARK_OK passer=1 kort=1 uden=1`.
2. Hash og kør `sql`, og forvent `SQL_OK b=2 r=0 u=0`.
3. Kør afgørelsesscriptet med `-v actor=…`.
4. Forvent 2 `accepted` med `method='relation-child-v1'`.
5. Kør derefter et preview over de to og forvent 2 egnede.
6. **Negativ:** et ark med `S` som token giver `SHEET_TOKEN_NOT_ALLOWED` og 0 filer i `$root`.

Afslut med `echo CHILD_SHEET_E2E_OK`.

Run: `bash $SCRATCH/mkdb.sh ci5b_childsheet writer && bash tests/sql/test-relation-child-sheet.sh ci5b_childsheet`
Expected: `CHILD_SHEET_E2E_OK`.

- [ ] **Step 7: Commit.**

```bash
git add schema.sql db-migrations.sql db-rls.sql db-verify.sql .claude/skills/daa-extract/scripts/relation_child_rows.sql \
  .claude/skills/daa-extract/scripts/relation_child_sheet.py .claude/skills/daa-extract/scripts/test_relation_child_sheet.py \
  tests/sql/fixtures/relation-child-e2e.sql tests/sql/test-relation-child-sheet.sh .github/workflows/ci.yml
git commit -m "feat(151): børnearket — projektion, ark og e2e (2b-iii)"
```

---

### Task 5: Core og web

**Files:**
- Modify: `packages/core/src/familieKilder.ts`
- Modify: `packages/core/src/__tests__/familieKilder.test.ts`
- Modify: `web/src/components/DetailPanel.tsx`
- Modify: `web/src/components/__tests__/DetailPanel.familieKilder.test.tsx`

**Interfaces:**
- Consumes: `public_family_sources` med `slags='boern'` og `counterpart_person_id` = forælderen (Task 3).
- Produces:
  - `FamilieKilde.slags: 'aegteskab' | 'foraelder' | 'boern'`;
  - `familieIderForPerson(...)` returnerer desuden `boerneFamilier: string[]`.

- [ ] **Step 1: Skriv de fejlende tests.**

I `familieKilder.test.ts` (den eksisterende model-fixture i filen har en union `f10` med børn; brug den):

```ts
it('boern godtages og boerneFamilier er partnerens familier med børn', () => {
  const rows = mapFamilieKilder([{ family_id: 10, slags: 'boern', counterpart_person_id: 1, source_record_ref: null,
    source_label: 'DAA X', record_label: 'Post 1', citation_label: 'c' }]);
  expect(rows).toHaveLength(1);
  expect(rows[0].slags).toBe('boern');
  expect(familieIderForPerson(m.indexes, '1').boerneFamilier).toEqual(['10']);
  expect(familieIderForPerson(m.indexes, '4').boerneFamilier).toEqual([]);
});
```

Tilpas fixture-id'erne til filens eksisterende model, hvis `f10`/`'1'` hedder noget andet. Det ledgeres som Ruling. Ret desuden den eksisterende forventning `toEqual({ aegteskaber: [], foraeldreFamilier: [] })` til også at indeholde `boerneFamilier: []`.

I `DetailPanel.familieKilder.test.tsx`, med samme mock-mønster som de eksisterende `foraelder`-tests:
- **(a)** Hos forælderen vises én kildelinje under »Børn«.
- **(b)** Hos barnet vises linjen ved den forælder, der er modpart, men ikke ved den anden forælder (Review Focus 5).
- **(c)** En ukendt `slags` springes over.

- [ ] **Step 2: Kør testene, og se dem fejle.**

Run: `npm run test -w @daa/core && npm run test -w web -- DetailPanel.familieKilder`
Expected: FAIL. `boern` frasorteres, og `boerneFamilier` er `undefined`.

- [ ] **Step 3: Implementér.** I `familieKilder.ts`:

```ts
export type FamilieKilde = {
  familyId: string;
  slags: 'aegteskab' | 'foraelder' | 'boern';
  // … uændret
};
```

`familieIderForPerson` får en tredje liste. Udvid løkken over `indexes.unionById`:

```ts
  const boerneFamilier = new Set<string>();
  for (const u of Object.values(indexes.unionById)) {
    const id = famId(u.id);
    if (!id) continue;
    if (u.p1 === focusId) aegteskaber.push({ spouseId: u.p2 ?? null, familyId: id });
    else if (u.p2 === focusId) aegteskaber.push({ spouseId: u.p1, familyId: id });
    if ((u.p1 === focusId || u.p2 === focusId) && (indexes.childrenByUnion[focusId]?.[u.id]?.length ?? 0) > 0) boerneFamilier.add(id);
  }
```

Returtypen udvides med `boerneFamilier: string[]`, og funktionen returnerer `{ aegteskaber, foraeldreFamilier: [...].sort(), boerneFamilier: [...boerneFamilier].sort() }`. I `mapFamilieKilder` erstattes betingelsen med:

```ts
    if (!r || (r.slags !== 'aegteskab' && r.slags !== 'foraelder' && r.slags !== 'boern')) continue;
```

I `DetailPanel.tsx`:
- `ids` får også `...boerneFamilier` med.
- Tilføj

```ts
  // Trin 5b 2b-iii: børneflokkens kilde hos forælderen (modparten er forælderen selv).
  const boerneKilder = familieKilder.filter((k) => k.slags === 'boern'
    && familieIder.boerneFamilier.includes(k.familyId) && k.counterpartPersonId === focusId);
```

- `foraelderKilder` udvides til `(k.slags === 'foraelder' || k.slags === 'boern')`. Den eksisterende betingelse (familien er barnets fødselsfamilie, og modparten er netop denne forælder) gør, at linjen kun vises ved den forælder, påstanden står hos.
- Under børnelisten (efter `</div>` i blokken `<Label>Børn</Label>`) indsættes:

```tsx
            {boerneKilder.map((k) => (
              <KildeLinjeVisning key={kildeNøgle(k)} kilde={k} versions={versionerForKilde} onVaelg={setBioVersionIdx} />
            ))}
```

- [ ] **Step 4: Kør testene og typecheck, og se dem bestå.**

Run: `npm run test -w @daa/core && npm run test -w web && npx tsc --noEmit -p mobile`
Expected: alle grønne. Mobil kompilerer, fordi typen kun er udvidet.

- [ ] **Step 5: Commit.**

```bash
git add packages/core/src/familieKilder.ts packages/core/src/__tests__/familieKilder.test.ts web/src/components/DetailPanel.tsx web/src/components/__tests__/DetailPanel.familieKilder.test.tsx
git commit -m "feat(151): web viser børneflokkens kilde ved forælder og barn"
```

---

### Task 6: Fuld lokal CI, bevis i restore og dokumenter

**Files:**
- Create: `docs/evidensbaseret-genimport/relationspersonas-5b-2b-iii-bevis.md`
- Modify: `docs/evidensbaseret-genimport/status.md` (ny række under 2b-ii runde 2), `docs/changelog.md` og `docs/decisions.md` (ny post øverst).
- Private: `~/.private/5b-2b-iii/` (0700). Genbrug kopier af `step.sh`, `hashes.sql`, `univers.sql`, `read.sql`, `bind-preview.sql` (prædikatlisten udvides med `'relation.child'`) og `bind.sql` fra `~/.private/5b-navneregel-v3/`. Rediger ikke originalerne.

- [ ] **Step 1: Fuld lokal CI.** Generér jobscripts med `gen_ci.py` (scratchpad) og kør alle 7 job, plus migrationsstien fra Task 2 Step 5.
  - Expected: 7/7 `CI_JOB_OK`.
  - En fejl i `writer-1939-v50-db`'s R-låsetest genkøres alene. Er den grøn alene, ledgeres en Ruling, som i runde 2.

- [ ] **Step 2: Arbejdsbase.**
  1. `createdb -T daa5b_navnv3_bevis_20261019200958 daa5b_2b_iii_bevis_<ts>`.
  2. Løft basen med `db-migrations.sql` og `db-rls.sql`, og kør `db-verify.sql` på en CI-opskriftsbase.
  3. **Før-målinger:** aggregat-hashes, 2a's tupel-digest, read og univers (heraf spanden for børn = 14), samt bindinger = 241.
  4. Tag kopierne `_neg` nu.

- [ ] **Step 3: Rækkefil og ark.**
  1. `relation_child_rows.sql` → `rows.json` (0600). Forventet: 14 rækker, `ok` 12, brud 2 (H3 og H1).
  2. `render` → `ark.txt`. Forventet: `ARK_OK passer=10 kort=2 uden=2`.
  3. **STOP:** projektejeren gennemgår arket med `open -e` og giver sha256 i chat.

- [ ] **Step 4: Afgørelse og binding.**
  1. `sql` → afgørelsesscript. Forventet med de forudfyldte svar: `SQL_OK b=12 r=0 u=0`.
  2. Kør scriptet.
  3. Bind-preview over `relation.child`: forventet 12 egnede og 0 genbindinger.
  4. Kør `bind.sql`. Forventet: bindinger 241 → 253 og efter-digest = manifest.
  5. Genkørsel: 0 egnede.

- [ ] **Step 5: Kontrolmålinger.**
  - Aggregat-hashes ens og 2a-digest uændret.
  - Read: kilderækker af typen `boern` +≤12; rapportér antallet, der falder fra pga. `family_offentlig`.
  - Univers: børnespanden 14 → 2.
  - Afgørelsernes `sheet_sha256` = godkendt hash (12).

- [ ] **Step 6: Negativtests i `_neg`.**
  - Et barn med egen post flyttet ud af en familie mellem afgørelse og binding ⇒ preview `RELATION_PROMOTION_STRUCTURE_INVALID`.
  - Forkert arkhash ⇒ `SHEET_HASH_MISMATCH`, 0 filer.
  - Direkte `same` på tilfælde 6 (H3) ⇒ `RELATION_CHILD_RULE_NOT_MET`.
  - Et ark med token `S` ⇒ `SHEET_TOKEN_NOT_ALLOWED`.

  Omdøb derefter kopien til `slet_<MMDD>__…` (karantæne) og skriv manifestet privat.

- [ ] **Step 7: Dokumenter** (kun tal og hashes).
  - **Rapporten:**
    - fordeling;
    - erratum §22.9 i korte tal;
    - binding;
    - læsning;
    - negativtests;
    - afvigelser;
    - at 2 påstande står `proposed`.
  - **`status.md` og `changelog.md`** dateres.
  - **`decisions.md`** får posten »BESLUTTET: børnehenvisningerne binder flokken til familien; ét ark for alle; drift via reglen (2026-10-20)«. Den henviser til spec'en og nævner projektejerens valg (A, køn, ét ark, regelbaseret drift).
  - **Commit:** `docs(151): 2b-iii bevist i restore — børneflokkene binder til familien`.

---

## Self-Review

1. **Spec coverage:**

   | Spec | Plan |
   | --- | --- |
   | §4 | Task 1 |
   | §5 | Task 2 (`relation_child_rule`) |
   | §6 writer | Task 2 |
   | §6 ark | Task 4 |
   | §7 | Task 2 (regelrækker) og Task 3 (tilstand, drift) |
   | §8 | Task 3 (SQL) og Task 5 (core/web) |
   | §9 | Task 1-6 |
   | §10 | Task 6-rapporten |
   | §3 »udenfor« | Respekteret. Mobil får kun typeudvidelsen via core. |

2. **Placeholders:** Fixture-SQL'en til e2e (Task 4 Step 6) og de to ekstra drift-transaktioner (Task 3 Step 1) er beskrevet med præcise værdier og mønsterfiler, ikke som fuld kode. Det er udførerens dokumenterede råderum med Ruling.
3. **Typer:**
   - `relation_child_rule`'s nøgler (`ok`, `brud`, `afvigelser`, `ref`, `family_id`, `principal_person_id`, `children`, `flock_digest`) bruges ens i Task 2, 3 og 4.
   - `slags 'boern'` er ens i Task 3 og 5.
   - Kontrakten `relation-child-sheet-input-v1` er ens i Task 4's SQL og Python.
4. **Review Focus:** hver linje har en navngiven test:

   | Linje | Test |
   | --- | --- |
   | 1 | Task 1 `test_ref_enkelt_nummer` og Task 2 »Enkelt nummer« |
   | 2 | Task 3 `$child_bind$` og transaktionen »uden for intervallet« |
   | 3 | Task 3 »ikke-offentligt medlem« |
   | 4 | Task 4 `test_ark_fejl` |
   | 5 | Task 5 (b) |
