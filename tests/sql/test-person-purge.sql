-- tests/sql/test-person-purge.sql — SQL-testene for fuld personsletning, grupperet pr. task.
-- Køres af tests/sql/test-person-purge.sh i en egen kopi af skabelonen pr. gruppe:
--   psql -d <kopi> -v gruppe=<navn> -f tests/sql/test-person-purge.sql
-- Hver test skriver én linje `OK <navn>`; en fejl afbryder med ON_ERROR_STOP. Output: kun sted-, tabel- og
-- kolonnenavne, aldrig rækkeindhold.
\set ON_ERROR_STOP on
\set QUIET on
\if :{?gruppe}
\else
  \echo 'PURGE_TEST_FEJL: angiv -v gruppe=<navn>'
  SELECT 1/0 AS gruppe_mangler;
\endif
SELECT :'gruppe' IN ('inventar') AS gruppe_kendt, :'gruppe'='inventar' AS g_inventar \gset
\if :gruppe_kendt
\else
  \echo 'PURGE_TEST_FEJL: ukendt gruppe'
  SELECT 1/0 AS gruppe_ukendt;
\endif

-- =====================================================================================================================
-- Gruppe inventar (Task 3): sletteinventar og katalogvagt pr. kolonne (K-1, K-4, V-7, K2-2).
-- Tabelnavne følger fixturens facit (purge_test.forventet): public-tabeller uden skema, private-tabeller med `private.`.
-- =====================================================================================================================
\if :g_inventar

-- Vagtreglen, defineret én gang: kandidatkolonner, der hverken står i et inventarsteds `kolonner` for samme tabel
-- eller i undtagelseslisten (kolonnen selv eller `*` for hele tabellen).
CREATE FUNCTION pg_temp.umatchede() RETURNS TABLE(tabel text, kolonne text) LANGUAGE sql STABLE AS $$
  SELECT k.tabel, k.kolonne
    FROM private.person_purge_kandidatkolonner() k
   WHERE NOT EXISTS (SELECT 1 FROM private.person_purge_inventar() i
                      WHERE i.tabel=k.tabel AND k.kolonne=ANY(i.kolonner))
     AND NOT EXISTS (SELECT 1 FROM private.person_purge_undtagelser() u
                      WHERE u.tabel=k.tabel AND u.kolonne IN (k.kolonne,'*'))
$$;

-- Bogens lag (Global Constraints) og dets underordnede tabeller. Literal; afledes ikke af funktionerne.
CREATE FUNCTION pg_temp.bogtabel(p_tabel text) RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT p_tabel IN (
      'private.source_record','private.source_record_occurrence','private.source_record_anchor_event',
      'private.source_record_placement','private.source_record_placement_decision','private.source_record_revision_event',
      'private.source_observation','private.source_observation_text','private.source_mention','private.source_rendition',
      'private.extraction_run','private.source_persona','private.source_persona_mention',
      'private.source_persona_placement','private.source_persona_placement_decision',
      'private.interpretation','private.interpretation_observation','private.interpretation_party',
      'private.identity_control_run','private.identity_control_sample','private.identity_control_event',
      'private.identity_control_exclusion','private.reimport_writer_profile','private.narrative_record_cutover_receipt',
      -- slettegraf §3.2: vocab/clause_disposition (l. 1125-1135) hører til bogens tabeller.
      'private.clause_disposition')
      -- Underordnede tabeller, der kommer til senere, er også bogens lag.
      OR p_tabel LIKE 'private.source\_record\_%' OR p_tabel LIKE 'private.source\_observation\_%'
      OR p_tabel LIKE 'private.source\_persona\_placement%'
$$;
-- Rene opslagstabeller uden P-sti (slettegraf §2.3 »øvrige«). Literal.
CREATE FUNCTION pg_temp.opslagstabel(p_tabel text) RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
  SELECT p_tabel IN ('source','place','estate','organisation','lineage','slaegt','vocab','private.vocab')
$$;

-- inventar_daekker_katalog: vagtreglen holder for hele kataloget.
DO $t$
DECLARE v text;
BEGIN
  SELECT string_agg(format('(%s, %s)',tabel,kolonne),', ' ORDER BY tabel,kolonne) INTO v FROM pg_temp.umatchede();
  IF v IS NOT NULL THEN
    RAISE EXCEPTION 'TEST_FAILED inventar_daekker_katalog: umatchede kandidatkolonner: %', v;
  END IF;
  IF (SELECT count(*) FROM private.person_purge_kandidatkolonner()) < 700 THEN
    RAISE EXCEPTION 'TEST_FAILED inventar_daekker_katalog: kandidatlisten er mistænkeligt kort (%)',
      (SELECT count(*) FROM private.person_purge_kandidatkolonner());
  END IF;
END $t$;
\echo OK inventar_daekker_katalog

-- vagt_ny_tabel: en ny tabel med en ren bigint-personkolonne uden FK fælder vagten — og kun den kolonne.
BEGIN;
CREATE TABLE public.tmp_purge_vagt(person_id bigint);
DO $t$
DECLARE v text[];
BEGIN
  SELECT array_agg(tabel||'.'||kolonne ORDER BY tabel,kolonne) INTO v FROM pg_temp.umatchede();
  IF v IS DISTINCT FROM ARRAY['tmp_purge_vagt.person_id'] THEN
    RAISE EXCEPTION 'TEST_FAILED vagt_ny_tabel: forventet {tmp_purge_vagt.person_id}, fik %', v;
  END IF;
END $t$;
DROP TABLE public.tmp_purge_vagt;
ROLLBACK;
\echo OK vagt_ny_tabel

-- vagt_ny_kolonne: en ny kolonne i en tabel, P kan efterlade spor i, fælder vagten — og kun den kolonne.
BEGIN;
ALTER TABLE public.story ADD COLUMN tmp_person bigint;
DO $t$
DECLARE v text[];
BEGIN
  SELECT array_agg(tabel||'.'||kolonne ORDER BY tabel,kolonne) INTO v FROM pg_temp.umatchede();
  IF v IS DISTINCT FROM ARRAY['story.tmp_person'] THEN
    RAISE EXCEPTION 'TEST_FAILED vagt_ny_kolonne: forventet {story.tmp_person}, fik %', v;
  END IF;
END $t$;
ALTER TABLE public.story DROP COLUMN tmp_person;
ROLLBACK;
\echo OK vagt_ny_kolonne
-- Begge midlertidige objekter er væk igen.
DO $t$
BEGIN
  IF to_regclass('public.tmp_purge_vagt') IS NOT NULL
     OR EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='public.story'::regclass AND attname='tmp_person') THEN
    RAISE EXCEPTION 'TEST_FAILED vagt_oprydning: midlertidigt objekt står tilbage';
  END IF;
END $t$;

-- inventar_ingen_bogtabel: ingen slet/nulstil/loesn-række har en tabel fra bogens lag.
DO $t$
DECLARE v text;
BEGIN
  SELECT string_agg(DISTINCT sted||':'||tabel,', ') INTO v FROM private.person_purge_inventar()
   WHERE handling IN ('slet','nulstil','loesn') AND pg_temp.bogtabel(tabel);
  IF v IS NOT NULL THEN RAISE EXCEPTION 'TEST_FAILED inventar_ingen_bogtabel: %', v; END IF;
END $t$;
\echo OK inventar_ingen_bogtabel

-- inventar_svarer_til_slettegraf: hvert sted i slettegraf §1 (S-/NY-/M-numre, delsteder) og »Afgørelser« Q6
-- (Prom_egen_fam) findes i inventaret, og omvendt. S52/S53/S55 står i slettegrafen i én tabelrække, men er tre
-- steder (subjekt, summary, fortrydelseskæde) og står hver for sig her. M1/M2 er reviewfund, ikke steder.
DO $t$
DECLARE
  v_liste text[] := ARRAY[
    -- §1a
    'S1','S2','S3','S4','S5','S6','S7','S8','S9','S10','S11a','S11b','S11c','S12',
    -- §1b
    'S13','S13b','S14','S14b','S15','S16','S17','S18','S19','S20','NY-A',
    -- §1c
    'S21','S22','S23','S23b','S24','S25','S26','S27','S28','S29','S30','S31','S32','NY-B','S32c','S33','S34','S34b',
    -- §1d
    'S35','S36','S37','S37b','S38','S38b',
    -- §1e (+ Q6)
    'S39a','S39b','S39c','Prom_egen_fam','S40','S41a','S41b','S42','S43a','S43b','S44a','S44b','S45a','M5','S45b',
    'S46','S47','S48','S49a','S49b','S49c','S49d','S50','S51','S58','NY-C','NY-D',
    -- §1f
    'S54','S57','S52','S53','S55','S52b','S56'];
  v_mangler text; v_ekstra text;
BEGIN
  IF cardinality(v_liste)<>(SELECT count(DISTINCT x) FROM unnest(v_liste) x) THEN
    RAISE EXCEPTION 'TEST_FAILED inventar_svarer_til_slettegraf: testlisten har dubletter';
  END IF;
  SELECT string_agg(x,', ') INTO v_mangler FROM unnest(v_liste) x
   WHERE NOT EXISTS (SELECT 1 FROM private.person_purge_inventar() i WHERE i.sted=x);
  SELECT string_agg(DISTINCT i.sted,', ') INTO v_ekstra FROM private.person_purge_inventar() i
   WHERE i.sted<>ALL(v_liste);
  IF v_mangler IS NOT NULL OR v_ekstra IS NOT NULL THEN
    RAISE EXCEPTION 'TEST_FAILED inventar_svarer_til_slettegraf: mangler [%], ukendte [%]', v_mangler, v_ekstra;
  END IF;
END $t$;
\echo OK inventar_svarer_til_slettegraf

-- undtagelse_hel_tabel_kun_bog: kolonne='*' kun for bogens lag og rene opslagstabeller.
DO $t$
DECLARE v text;
BEGIN
  SELECT string_agg(tabel,', ' ORDER BY tabel) INTO v FROM private.person_purge_undtagelser()
   WHERE kolonne='*' AND NOT (pg_temp.bogtabel(tabel) OR pg_temp.opslagstabel(tabel));
  IF v IS NOT NULL THEN RAISE EXCEPTION 'TEST_FAILED undtagelse_hel_tabel_kun_bog: %', v; END IF;
END $t$;
\echo OK undtagelse_hel_tabel_kun_bog

-- inventar_vaerdier: handling/grund/fase i de tilladte værdimængder; historikken og bevarede/blokerede steder har
-- ingen grund (M2-4); slette-, nulstil- og løsnesteder i fase 2-11 har en.
DO $t$
DECLARE v text;
BEGIN
  SELECT string_agg(DISTINCT sted,', ') INTO v FROM private.person_purge_inventar()
   WHERE sted IS NULL OR tabel IS NULL OR coalesce(cardinality(kolonner),0)=0
      OR handling IS NULL OR handling NOT IN ('slet','nulstil','loesn','bevar_andres','blokér','ingen')
      OR (grund IS NOT NULL AND grund NOT IN ('egen','hel_stroem','andres_ref','afledt','familie'))
      OR (handling IN ('bevar_andres','blokér','ingen') AND grund IS NOT NULL)
      OR (handling='blokér' AND fase IS DISTINCT FROM '0')
      OR (handling IN ('slet','nulstil','loesn') AND fase IS NULL)
      OR (handling IN ('slet','nulstil','loesn') AND tabel IN ('change_event','change_set') AND grund IS NOT NULL)
      OR (handling IN ('slet','nulstil','loesn') AND tabel NOT IN ('change_event','change_set') AND grund IS NULL);
  IF v IS NOT NULL THEN RAISE EXCEPTION 'TEST_FAILED inventar_vaerdier: %', v; END IF;
END $t$;
\echo OK inventar_vaerdier

-- inventar_syv_bigint (K2-2): de syv rene bigint-person-/familiekolonner uden FK står i inventaret.
DO $t$
DECLARE v text;
BEGIN
  SELECT string_agg(t||'.'||k,', ') INTO v
    FROM (VALUES ('private.reimport_event','canonical_person_id'),
                 ('private.reimport_name_completion_result','person_id'),
                 ('private.legacy_placement_disposition','person_id'),
                 ('private.identity_control_parent_card','counterpart_person_id'),
                 ('private.identity_control_parent_card','family_id'),
                 ('private.relation_reopen','from_family_id'),
                 ('private.relation_reopen','to_family_id'),
                 ('private.marriage_ordinal_correction','family_id')) x(t,k)
   WHERE NOT EXISTS (SELECT 1 FROM private.person_purge_inventar() i WHERE i.tabel=x.t AND x.k=ANY(i.kolonner));
  IF v IS NOT NULL THEN RAISE EXCEPTION 'TEST_FAILED inventar_syv_bigint: %', v; END IF;
END $t$;
\echo OK inventar_syv_bigint

-- inventar_kolonner_findes: hver navngiven (tabel, kolonne) i inventar og undtagelser findes i kataloget (en
-- stavefejl ville ellers stå som en død post), og ingen kolonne er både inventar og undtagelse.
DO $t$
DECLARE v text; v2 text; v3 text;
BEGIN
  WITH navngivet AS (
    SELECT tabel, k AS kolonne FROM private.person_purge_inventar(), unnest(kolonner) k
    UNION SELECT tabel, kolonne FROM private.person_purge_undtagelser() WHERE kolonne<>'*'),
  katalog AS (
    SELECT CASE WHEN n.nspname='public' THEN c.relname ELSE n.nspname||'.'||c.relname END AS tabel, a.attname::text AS kolonne
      FROM pg_attribute a JOIN pg_class c ON c.oid=a.attrelid JOIN pg_namespace n ON n.oid=c.relnamespace
     WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','p') AND a.attnum>0 AND NOT a.attisdropped)
  SELECT string_agg(tabel||'.'||kolonne,', ' ORDER BY tabel,kolonne) INTO v
    FROM navngivet WHERE (tabel,kolonne) NOT IN (SELECT tabel,kolonne FROM katalog);
  SELECT string_agg(u.tabel,', ') INTO v2 FROM private.person_purge_undtagelser() u
   WHERE u.kolonne='*' AND to_regclass(CASE WHEN u.tabel LIKE 'private.%' THEN u.tabel ELSE 'public.'||u.tabel END) IS NULL;
  SELECT string_agg(u.tabel||'.'||u.kolonne,', ') INTO v3 FROM private.person_purge_undtagelser() u
   WHERE u.kolonne<>'*' AND EXISTS (SELECT 1 FROM private.person_purge_inventar() i
                                     WHERE i.tabel=u.tabel AND u.kolonne=ANY(i.kolonner));
  IF v IS NOT NULL OR v2 IS NOT NULL OR v3 IS NOT NULL THEN
    RAISE EXCEPTION 'TEST_FAILED inventar_kolonner_findes: ukendte [%], ukendte *-tabeller [%], både inventar og undtagelse [%]',
      v, v2, v3;
  END IF;
  IF EXISTS (SELECT tabel,kolonne FROM private.person_purge_undtagelser() GROUP BY 1,2 HAVING count(*)>1)
     OR EXISTS (SELECT 1 FROM private.person_purge_undtagelser() WHERE nullif(btrim(begrundelse),'') IS NULL) THEN
    RAISE EXCEPTION 'TEST_FAILED inventar_kolonner_findes: undtagelse uden begrundelse eller dublet';
  END IF;
END $t$;
\echo OK inventar_kolonner_findes

\endif
