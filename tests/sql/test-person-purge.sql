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
SELECT :'gruppe' IN ('inventar','binding','plan','historik','fortrydelse','manifest') AS gruppe_kendt,
       :'gruppe'='inventar' AS g_inventar, :'gruppe'='binding' AS g_binding,
       :'gruppe'='plan' AS g_plan, :'gruppe'='historik' AS g_historik, :'gruppe'='fortrydelse' AS g_fortrydelse, :'gruppe'='manifest' AS g_manifest \gset
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


-- =====================================================================================================================
-- Gruppe binding (Task 4b / Q6, R21): et rigtigt strukturelt bindingsgrundlag og en beregnet state_sha256.
-- Observeret og accepteret adfærd (R29): NULL-state og præcis RELATION_REOPEN_STATE_INVALID,
-- når P er part. Testen ændrer ingen append-only-vagt.
-- Promotionen bliver stående: Task 5/8 leverer slettevejen; state-funktionen læser ikke promotionen.
-- =====================================================================================================================
\if :g_binding
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql

DO $binding_forsvinder$
DECLARE
  v_actor uuid := 'a2a00000-0000-4000-8000-00000000a001';
  v_source bigint; v_src jsonb; v_other_source bigint; v_other_src jsonb; v_control uuid; v_m jsonb; v_items jsonb; v_preview jsonb;
  v_i uuid; v_version integer; v_hash text; v_promotion uuid; v_error text;
  v_invalid jsonb; v_good jsonb; v_other jsonb; v_other_hash text; v_child jsonb; v_parent jsonb; v_parent_i uuid; v_parent_key uuid;
  v_family bigint := purge_test.id('fam_keep');
  v_p bigint := purge_test.id('P');
  v_context jsonb := jsonb_build_object('basis','human_sheet','line',1,
    'sheet_sha256',repeat('1',64),'rows_sha256',repeat('2',64));
BEGIN
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  PERFORM purge_test.nyt();
  -- red_opret_person opretter privat=true. Som test-family-sources.sql/fixtures/person-facts.sql kræver
  -- denne publiceringsprøve offentlige, afdøde narrativsubjekter. Kun denne gruppes rollback-kopi ændres;
  -- den rigtige publiceringspolitik og f2a_publish bruges uændret.
  UPDATE public.person SET levende=false,privat=false,staged=false
    WHERE id IN (v_p,purge_test.id('barn'));
  -- Ny kilde med positivt sekvens-id; ingen ændring af fixturens syntetiske prom_egen_fam-hash (R21).
  v_source := nextval(pg_get_serial_sequence('public.source','id'));
  v_src := pg_temp.f5b_source(v_source);
  -- Samme kilde/persona/party-kæde som de eksisterende relations-tests, men på fixturens P og anden_partner.
  -- false: brug den eksisterende familie med barn; opret ikke et konkurrerende ægteskab.
  v_m := pg_temp.f2a_marriage(v_source,v_src,'PURGE-Q6',v_p,purge_test.id('anden_partner'),v_actor,2,2,false);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  SET LOCAL ROLE authenticated;
  v_preview := public.red_preview_relation_decisions(v_source);
  IF public.red_decide_relation_interpretations(v_source,v_preview->>'set_sha256') IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'TEST_FAILED binding_forsvinder: præcis én strukturel afgørelse kræves';
  END IF;
  RESET ROLE;
  SELECT i.id,i.version INTO STRICT v_i,v_version FROM private.interpretation_current i
   WHERE i.interpretation_key=(v_m->'claim'->>'key')::uuid;
  v_items := jsonb_build_array(jsonb_build_object('interpretation_id',v_i::text,'family_id',v_family));
  SET LOCAL ROLE authenticated;
  v_preview := public.red_preview_relation_promotions(v_source,v_items);
  IF (v_preview#>>'{items,0,eligible}')::boolean IS DISTINCT FROM true THEN
    RAISE EXCEPTION 'TEST_FAILED binding_forsvinder: strukturel binding kunne ikke oprettes';
  END IF;
  PERFORM public.red_promote_relation_interpretations_batch(v_source,v_items,v_preview->>'preview_sha256');
  RESET ROLE;
  SELECT p.id,p.evidence->>'state_sha256' INTO STRICT v_promotion,v_hash
    FROM private.interpretation_promotion p WHERE p.interpretation_id=v_i AND p.target_type='family';
  IF v_hash IS NULL OR v_hash IS DISTINCT FROM private.relation_binding_state_sha256(v_i) THEN
    RAISE EXCEPTION 'TEST_FAILED binding_forsvinder: udgangspunktet har ikke en gældende bindingshash';
  END IF;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;

  -- En separat forælderfortolkning på barnets post til den tilbageværende partner i samme familie.
  -- P's ægteskab og barnets forælderbinding publiceres, så public_family_sources faktisk har to kilder før.
  v_other_source:=nextval(pg_get_serial_sequence('public.source','id'));
  v_other_src:=pg_temp.f5b_source(v_other_source);
  v_parent:=pg_temp.f5b_post(v_other_source,v_other_src,'PURGE-Q6-PARENT','Far Alfa.',ARRAY['Far Alfa.'],purge_test.id('anden_partner'),v_actor);
  v_child:=pg_temp.f5b_post(v_other_source,v_other_src,'PURGE-Q6-CHILD','Barn Alfa. søn af Far.',ARRAY['Barn Alfa.','søn af Far.'],purge_test.id('barn'),v_actor);
  PERFORM pg_temp.f2a_event_for_state((v_parent->>'principal')::uuid);
  PERFORM pg_temp.f2a_event_for_state((v_child->>'principal')::uuid);
  v_other:=pg_temp.f5b_claim(v_other_source,v_other_src,'relation.parent',(v_child->'clauses'->>1)::uuid,'søn af Far.');
  v_parent_key:=(v_other->>'key')::uuid;
  INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,post_offset,origin,origin_ref)
    VALUES (v_parent_key,'principal',1,(v_child->>'principal')::uuid,11,'relation_persona',gen_random_uuid());
  SET LOCAL ROLE authenticated;
  PERFORM public.red_afgoer_relation_interpretation(v_parent_key,1,'same',v_family,'Q6: anden forælder','{}');
  RESET ROLE;
  SELECT id INTO STRICT v_parent_i FROM private.interpretation_current WHERE interpretation_key=v_parent_key;
  v_other:=jsonb_build_array(jsonb_build_object('interpretation_id',v_parent_i::text,'family_id',v_family));
  v_preview:=private.preview_relation_promotions(v_other_source,v_other,false);
  SET LOCAL ROLE authenticated;
  PERFORM public.red_promote_relation_interpretations_batch(v_other_source,v_other,v_preview->>'preview_sha256');
  RESET ROLE;
  v_other_hash:=private.relation_binding_state_sha256(v_parent_i);
  IF v_other_hash IS NULL THEN RAISE EXCEPTION 'TEST_FAILED binding_andres_bevaret: udgangspunkt NULL'; END IF;
  PERFORM pg_temp.f2a_publish(v_source,v_src,v_m->'post',v_p,v_actor,'Anna Alfa. Gift med Bo Beta.');
  PERFORM pg_temp.f2a_publish(v_other_source,v_other_src,v_child,purge_test.id('barn'),v_actor,'Barn Alfa. søn af Far.');
  IF (SELECT count(*) FROM public.public_family_sources(ARRAY[v_family]))<>2 THEN
    RAISE EXCEPTION 'TEST_FAILED binding_andres_bevaret: to offentlige kilder kræves før';
  END IF;
  -- Den del af sletningen, der alene er nok til at gøre bindingsgrundlaget ugyldigt. Promotionen beholdes:
  -- Task 5/8 har endnu ikke bygget et lovligt DELETE af append-only-rækken. relation_binding_state læser
  -- aldrig promotionen, så dens tilstedeværelse kan ikke ændre NULL-resultatet nedenfor.
  PERFORM purge_test.nyt();
  DELETE FROM public.family_member WHERE family_id=v_family AND person_id=v_p;
  IF NOT EXISTS (SELECT 1 FROM public.family WHERE id=v_family)
     OR NOT EXISTS (SELECT 1 FROM public.family_member WHERE family_id=v_family AND person_id=purge_test.id('barn'))
     OR NOT EXISTS (SELECT 1 FROM private.interpretation_promotion WHERE id=v_promotion) THEN
    RAISE EXCEPTION 'TEST_FAILED binding_forsvinder: bevaret familie/barn/binding mangler';
  END IF;
  IF private.relation_binding_state(v_i) IS NOT NULL THEN
    RAISE EXCEPTION 'TEST_FAILED binding_forsvinder: bindingens struktur blev ikke ugyldig';
  END IF;
  IF private.relation_binding_state_sha256(v_i) IS NOT NULL THEN
    RAISE EXCEPTION 'TEST_FAILED binding_forsvinder: NULL-state skal give NULL-hash';
  END IF;
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM public.red_genaabn_relation_interpretation(v_i,v_version,'Q6: P fjernet fra bevaret familie',v_context);
    RESET ROLE;
    RAISE EXCEPTION 'TEST_FAILED binding_forsvinder: genåbning blev accepteret';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    IF v_error IS DISTINCT FROM 'RELATION_REOPEN_STATE_INVALID' THEN RAISE; END IF;
  END;
  -- Både læse- og låsegrenen skal give en item-afvisning, aldrig kaste på familien som helhed.
  v_preview:=private.preview_relation_promotions(v_source,v_items,false);
  IF v_preview#>>'{items,0,reason_code}' IS DISTINCT FROM 'RELATION_PROMOTION_STRUCTURE_INVALID'
     OR private.preview_relation_promotions(v_source,v_items,true)#>>'{items,0,reason_code}'
          IS DISTINCT FROM 'RELATION_PROMOTION_STRUCTURE_INVALID' THEN
    RAISE EXCEPTION 'TEST_FAILED binding_forsvinder: preview af NULL-state';
  END IF;
  BEGIN
    PERFORM private.append_relation_classification(v_i,'ordinal_beholdt','{"fixture":"purge"}');
    RAISE EXCEPTION 'TEST_FAILED binding_forsvinder: klassifikation blev accepteret';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    IF v_error IS DISTINCT FROM 'RELATION_CLASSIFICATION_STRUCTURE_INVALID' THEN RAISE; END IF;
  END;
  IF EXISTS (SELECT 1 FROM private.text_revision_binding_set(ARRAY[(v_m->'claim'->>'key')::uuid])) THEN
    RAISE EXCEPTION 'TEST_FAILED binding_forsvinder: tekstrevision regner NULL-binding som gældende';
  END IF;
  -- Hele kilden kan stadig behandles: ét nyt proposed-ægteskab med NULL-state skal springes over,
  -- mens en uafhængig proposed-påstand i SAMME kilde afgøres normalt.
  v_invalid:=pg_temp.f2a_marriage(v_source,v_src,'PURGE-Q6-INVALID',v_p,purge_test.id('anden_partner'),v_actor,2,2,false);
  v_good:=pg_temp.f2a_marriage(v_source,v_src,'PURGE-Q6-GOOD',purge_test.id('nabo'),purge_test.id('tredje'),v_actor,1,1,false);
  IF private.relation_binding_state((v_invalid->'claim'->>'id')::uuid) IS NOT NULL THEN
    RAISE EXCEPTION 'TEST_FAILED binding_andres_bevaret: ugyldig proposed fik state';
  END IF;
  v_preview:=private.relation_decision_set(v_source);
  IF (v_preview->>'count')::int IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'TEST_FAILED binding_andres_bevaret: kun den uafhængige påstand skal vælges';
  END IF;
  PERFORM private.spouse_exception_projection(v_source);
  v_preview:=private.relation_decision_set(v_source);
  SET LOCAL ROLE authenticated;
  IF public.red_decide_relation_interpretations(v_source,v_preview->>'set_sha256') IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'TEST_FAILED binding_andres_bevaret: uafhængig afgørelse blev blokeret';
  END IF;
  RESET ROLE;
  IF private.relation_binding_state(v_parent_i) IS NULL
     OR private.relation_binding_state_sha256(v_parent_i) IS DISTINCT FROM v_other_hash THEN
    RAISE EXCEPTION 'TEST_FAILED binding_andres_bevaret: barnets binding til tilbageværende partner blev ændret';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM private.text_revision_binding_set(ARRAY[v_parent_key])) THEN
    RAISE EXCEPTION 'TEST_FAILED binding_andres_bevaret: barnets binding sprang over';
  END IF;
  IF (SELECT count(*) FROM public.public_family_sources(ARRAY[v_family]))<>1 THEN
    RAISE EXCEPTION 'TEST_FAILED binding_andres_bevaret: familievisning skal kun beholde barnets gyldige kilde';
  END IF;
  -- Fixturens failed-kontrolkørsel returnerer 0; den afhænger ikke af NULL-bindingsstate.
  v_control:=purge_test.u('kontrolkoersel');
  SET LOCAL ROLE authenticated;
  IF public.red_corroborate_family_identities(v_control,repeat('0',64)) IS DISTINCT FROM 0 THEN
    RAISE EXCEPTION 'TEST_FAILED binding_familiebekraeftelse: failed-kørsel';
  END IF;
  RESET ROLE;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
END $binding_forsvinder$;
ROLLBACK;
\echo OK binding_forsvinder
\echo OK binding_andres_bevaret
\echo OK binding_familiebekraeftelse
\endif

-- =====================================================================================================================
-- Task 4: plan. Tællertal kopieres af harnessen fra den uafhængige tæller til skabelonen (kun sted/antal).
-- En enkelt gruppe køres på en kopi af denne skabelon. Ingen dynamisk SQL i produktionsfunktionerne.
-- =====================================================================================================================
\if :g_plan
BEGIN;
CREATE TEMP TABLE plan ON COMMIT DROP AS SELECT * FROM private.person_purge_plan(purge_test.id('P'));

DO $t$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM plan) OR EXISTS (
    SELECT 1 FROM plan p WHERE NOT EXISTS (SELECT 1 FROM private.person_purge_inventar() i
      WHERE (i.sted,i.tabel,i.handling)=(p.sted,p.tabel,p.handling)
        AND i.grund IS NOT DISTINCT FROM p.grund AND i.fase IS NOT DISTINCT FROM p.fase)) THEN
    RAISE EXCEPTION 'TEST_FAILED plan_matcher_inventar';
  END IF;
  IF EXISTS (SELECT tabel,pk FROM plan GROUP BY 1,2 HAVING count(*)<>1) THEN
    RAISE EXCEPTION 'TEST_FAILED plan_matcher_inventar: dobbelttalte rækker (M3/S19/NY-B/S24)';
  END IF;
  IF EXISTS (SELECT 1 FROM plan WHERE tabel LIKE 'public.%') OR EXISTS (
    SELECT 1 FROM plan WHERE tabel='private.source_persona_identity' AND
      (ekstra->>'forrige_version')::int IS DISTINCT FROM
        (SELECT max(e.version) FROM private.source_persona_identity_event e WHERE e.source_persona_id=(pk->>'source_persona_id')::uuid)) THEN
    RAISE EXCEPTION 'TEST_FAILED plan_matcher_inventar: R24/Q7';
  END IF;
END $t$;
\echo OK plan_matcher_inventar

-- R25: kanoniske steder (venstre) -> tælleretiketter (højre). S19 og NY-B ejes én gang i planen,
-- men tælleren viser dem også som delmængder af S14/S32. Derfor sammenlignes disjunkte unionsmængder.
-- S24: mellemliggende nulstilling af latest_event_id er i ekstra; facit/inventarets slet-række tælles én gang.
CREATE TEMP TABLE count_map(kanonisk text[], taeller text[]) ON COMMIT DROP;
INSERT INTO count_map VALUES
 ('{S1}','{S01}'),('{S2}','{S02}'),('{S3}','{S03,S03b}'),('{S4}','{S04}'),('{S5}','{S05}'),
 ('{S6}','{S06}'),('{S7}','{S07}'),('{S8}','{S08}'),('{S9}','{S09}'),('{S10}','{S10}'),
 ('{S12}','{S12}'),('{S13}','{S13}'),('{S13b}','{S13b}'),('{S14,S19}','{S14}'),('{S19}','{S19}'),('{S14b}','{S14b}'),
 ('{S15}','{S15,S15b}'),('{S16}','{S16,S16b}'),('{S17}','{S17,S17b}'),('{S18}','{S18,S18b}'),
 ('{S20}','{S20}'),('{S21}','{S21,S21b}'),('{S22}','{S22}'),('{S23}','{S23}'),('{S24}','{S24}'),
 ('{S25,S26}','{S25,S25b,S26}'),('{S27}','{S27}'),('{S28}','{S28}'),('{S30}','{S30,S30b,S30c}'),
 ('{S31}','{S31}'),('{S32,NY-B}','{S32}'),('{S33}','{S33,S33b}'),('{S34}','{S34,S34c}'),
 ('{S35}','{S35}'),('{S36}','{S36}'),('{S37}','{S37c}'),('{S38}','{S38}'),
 ('{S39a,Prom_egen_fam}','{S39}'),('{S40}','{S40}'),('{S41a}','{S41}'),('{S42}','{S42}'),
 ('{S43a}','{S43}'),('{S45a}','{S45}'),('{M5}','{M5}'),('{S49a}','{S49}'),('{S49b}','{S49b}'),('{S54}','{S54}');
-- Afvigelser i den eksisterende tæller, afgrænset og testet:
-- * S11 tæller kun canonical_person_id=P, mens planen tager hele X2-strømmen (v1/v2 = to ekstra events).
-- * S52/S53/S55/S54b er kandidatsæt/heuristik, ikke D (§2.4); D sammenlignes præcist med facit nedenfor.
-- * S37c tæller storage-stier; alle fixturens eksklusive medier har en sti (assert nedenfor), så antal = rækker.
-- * S22/S23/S24 og S28's tæller er smallere end planen uden for fixturen (familienarrativer/andre note-targets).
-- * S29 og NY-A testes i Task 7's blokeringsgrupper; fixturen har ingen token til slettemål.
-- * Øvrige etiketter er bevar_andres/info/overlappende delmængder og er ikke sletteantal.
DO $t$
DECLARE r record; v_plan bigint; v_count bigint;
BEGIN
  FOR r IN SELECT * FROM count_map LOOP
    IF (SELECT count(*) FROM purge_test.counts WHERE sted=ANY(r.taeller))<>cardinality(r.taeller) THEN
      RAISE EXCEPTION 'TEST_FAILED plan_matcher_count: manglende tælleretiket %',r.taeller;
    END IF;
    SELECT count(*) INTO v_plan FROM plan WHERE sted=ANY(r.kanonisk) AND handling<>'bevar_andres';
    SELECT sum(antal) INTO v_count FROM purge_test.counts WHERE sted=ANY(r.taeller);
    IF v_plan IS DISTINCT FROM v_count THEN
      RAISE EXCEPTION 'TEST_FAILED plan_matcher_count: % plan=% count=%',r.kanonisk,v_plan,v_count;
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM plan WHERE sted IN ('S11a','S11b')) IS DISTINCT FROM
       (SELECT antal+2 FROM purge_test.counts WHERE sted='S11')
     OR (SELECT count(*) FROM private.source_persona_identity_event
          WHERE source_persona_id=purge_test.u('X2') AND canonical_person_id IS DISTINCT FROM purge_test.id('P'))<>2 THEN
    RAISE EXCEPTION 'TEST_FAILED plan_matcher_count: kendt S11-afvigelse er ikke præcis X2 v1/v2';
  END IF;
  IF EXISTS (SELECT 1 FROM plan WHERE sted='S37' AND ekstra->>'storage_path' IS NULL) THEN
    RAISE EXCEPTION 'TEST_FAILED plan_matcher_count: S37c kan ikke sidestilles med antal rækker';
  END IF;
  -- Alle muterende steder er dækket af mappingen eller den navngivne S11-/D-/nul-blokering-undtagelse.
  IF EXISTS (SELECT 1 FROM plan p WHERE p.handling<>'bevar_andres'
      AND p.sted NOT IN ('S11a','S11b','S52','S53','S55','S29','S34b','NY-A','S39b','S49d')
      AND NOT EXISTS (SELECT 1 FROM count_map m WHERE p.sted=ANY(m.kanonisk))) THEN
    RAISE EXCEPTION 'TEST_FAILED plan_matcher_count: umappet sted';
  END IF;
END $t$;
\echo OK plan_matcher_count

-- R25: fixturens S33b er inventarets S33. Resten af delstedsnavnene er allerede kanoniske.
DO $t$
DECLARE v_missing bigint; v_extra bigint;
BEGIN
  SELECT count(*) INTO v_missing FROM (
    SELECT tabel,pk,handling FROM purge_test.forventet
    EXCEPT SELECT tabel,pk,handling FROM plan WHERE handling IN ('slet','nulstil','loesn')) q;
  SELECT count(*) INTO v_extra FROM (
    SELECT tabel,pk,handling FROM plan WHERE handling IN ('slet','nulstil','loesn')
    EXCEPT SELECT tabel,pk,handling FROM purge_test.forventet) q;
  IF v_missing<>0 OR v_extra<>0 THEN
    RAISE EXCEPTION 'TEST_FAILED plan_lig_facit: mangler=% ekstra=%',v_missing,v_extra;
  END IF;
  IF EXISTS (SELECT 1 FROM purge_test.sted f JOIN plan p USING(tabel,pk)
      WHERE p.sted IS DISTINCT FROM CASE f.sted WHEN 'S33b' THEN 'S33' ELSE f.sted END) THEN
    RAISE EXCEPTION 'TEST_FAILED plan_lig_facit: delstedsmapping';
  END IF;
  IF EXISTS (SELECT 1 FROM plan WHERE handling='blokér') THEN
    RAISE EXCEPTION 'TEST_FAILED plan_lig_facit: fixturen skal kunne slettes';
  END IF;
END $t$;
\echo OK plan_lig_facit
ROLLBACK;

-- Q5: R ∩ R_fam må ikke skjule familieejerskab, heller ikke for relationens assertions.
BEGIN;
DO $q5$
DECLARE v_rel bigint; v_assertion bigint; v_i uuid; v_template private.interpretation%ROWTYPE;
  v_other uuid:=purge_test.u('T1'); v_prom uuid[]:='{}'; v_id uuid; r record;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','a2a00000-0000-4000-8000-00000000a001',true);
  PERFORM purge_test.nyt();
  IF NOT EXISTS (SELECT 1 FROM private.source_persona_identity
    WHERE source_persona_id=v_other AND canonical_person_id=purge_test.id('tredje') AND decision_status='accepted') THEN
    RAISE EXCEPTION 'TEST_FAILED plan_q5_overlap: andens persona mangler';
  END IF;
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('person',purge_test.id('P'),'fact',purge_test.id('fakta_vielse_del'),'omtaler') RETURNING id INTO v_rel;
  INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst)
    VALUES ('relation',v_rel,'Syntetisk familieudsagn') RETURNING id INTO v_assertion;
  SELECT i.* INTO STRICT v_template FROM private.interpretation i JOIN private.interpretation_promotion p
    ON p.interpretation_id=i.id WHERE p.id=purge_test.u('prom_egen');
  INSERT INTO private.interpretation(interpretation_key,version,source_id,source_persona_id,interpretation_kind,
    predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
    VALUES (gen_random_uuid(),1,v_template.source_id,v_other,v_template.interpretation_kind,
      v_template.predicate,v_template.value,v_template.schema_version,v_template.derivation_kind,1,'proposed','fixture',v_template.extraction_run_id)
    RETURNING id INTO v_i;
  INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
    SELECT v_i,observation_id,evidence_role,ordinal FROM private.interpretation_observation WHERE interpretation_id=v_template.id;
  v_i:=public.red_decide_interpretation(v_i,1,'accepted','{"basis":"purge-q5-overlap"}');
  FOR r IN SELECT * FROM (VALUES ('relation',v_rel),('assertion',v_assertion)) t(typ,id) LOOP
    INSERT INTO private.interpretation_promotion(interpretation_id,target_type,target_id,evidence,promoted_by,promoted_by_name)
      VALUES (v_i,r.typ,r.id,'{"fixture":"q5-overlap"}','a2a00000-0000-4000-8000-00000000a001','Purge-redaktør')
      RETURNING id INTO v_id;
    v_prom:=array_append(v_prom,v_id);
  END LOOP;
  IF (SELECT count(*) FROM private.person_purge_plan(purge_test.id('P')) q
    WHERE q.tabel='private.interpretation_promotion' AND q.pk->>'id'=ANY(v_prom::text[])
      AND q.sted='S39b' AND q.handling='blokér')<>2
    OR EXISTS (SELECT 1 FROM private.person_purge_plan(purge_test.id('P')) q
      WHERE q.tabel='private.interpretation_promotion' AND q.pk->>'id'=ANY(v_prom::text[]) AND q.handling='slet') THEN
    RAISE EXCEPTION 'TEST_FAILED plan_q5_overlap: andres promotions skal blokere';
  END IF;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
END $q5$;
\echo OK plan_q5_overlap
ROLLBACK;

BEGIN;
DO $null_subject$
DECLARE v_ids bigint[]; v_id bigint; v_citation bigint; r record;
BEGIN
  -- Begge NULL samt hver delvist NULL kombination. Tokenfeltet er payload; øvrige felter er NULL.
  FOR r IN SELECT * FROM (VALUES (NULL::text,NULL::bigint),('person',NULL::bigint),
    (NULL::text,purge_test.id('P'))) t(typ,id) LOOP
    INSERT INTO public.suggestion(subjekt_type,subjekt_id,payload)
      VALUES (r.typ,r.id,jsonb_build_object('text',format('[[person:%s|Navn]]',purge_test.id('P')))) RETURNING id INTO v_id;
    v_ids:=array_append(v_ids,v_id);
  END LOOP;
  IF (SELECT count(*) FROM private.person_purge_plan(purge_test.id('P'))
    WHERE tabel='suggestion' AND (pk->>'id')::bigint=ANY(v_ids) AND sted='S34b' AND handling='blokér')<>3 THEN
    RAISE EXCEPTION 'TEST_FAILED plan_null_subjekt_token';
  END IF;
  -- Samme NULL-fejl fandtes i S29's komplement på citation.assertion_id (kolonnen tillader NULL).
  INSERT INTO public.citation(assertion_id,citat_tekst)
    VALUES (NULL,format('[[person:%s|Navn]]',purge_test.id('P'))) RETURNING id INTO v_citation;
  IF NOT EXISTS (SELECT 1 FROM private.person_purge_plan(purge_test.id('P'))
    WHERE tabel='citation' AND pk=jsonb_build_object('id',v_citation) AND sted='S29' AND handling='blokér') THEN
    RAISE EXCEPTION 'TEST_FAILED plan_null_citation_token';
  END IF;
END $null_subject$;
\echo OK plan_null_subjekt_token
\echo OK plan_null_citation_token
ROLLBACK;

-- Sammenlign S48 med det oprindelige prædikat på en positiv kontekst og flere kandidater pr. persona.
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
DO $s48$
DECLARE v_source bigint:=nextval(pg_get_serial_sequence('public.source','id')); v_src jsonb; v_m jsonb;
  v_actor uuid:='a2a00000-0000-4000-8000-00000000a001'; v_run uuid; v_spouse uuid;
  v_old uuid[]; v_new uuid[];
BEGIN
  PERFORM purge_test.nyt();
  v_src:=pg_temp.f5b_source(v_source);
  -- Nabo er ikke medlem af P's familier. Konteksten skal findes via principal=P, ikke spouse=nabo.
  v_m:=pg_temp.f2a_marriage(v_source,v_src,'PURGE-S48',purge_test.id('P'),purge_test.id('nabo'),v_actor,1,1,false);
  v_spouse:=(v_m->>'spouse_persona')::uuid;
  INSERT INTO private.source_persona_identity_candidate_run(source_id,generator_version,config,config_sha256,input_spec,
    input_sha256,candidates_sha256,persona_count,candidate_count,created_by,created_by_name)
    VALUES (v_source,'fixture','{}',repeat('1',64),'{}',repeat('2',64),repeat('3',64),1,2,v_actor,'Purge-redaktør') RETURNING id INTO v_run;
  INSERT INTO private.source_persona_identity_candidate(run_id,source_persona_id,candidate_person_id,rank,score,tier,basis)
    VALUES (v_run,v_spouse,purge_test.id('nabo'),1,0.9,'review','{"fixture":"s48"}'),
           (v_run,v_spouse,purge_test.id('tredje'),2,0.8,'review','{"fixture":"s48"}');
  SELECT coalesce(array_agg(t.id ORDER BY t.id),'{}') INTO v_old FROM private.source_persona_identity_candidate t
    WHERE t.candidate_person_id<>purge_test.id('P') AND EXISTS (
      SELECT 1 FROM jsonb_array_elements(private.persona_family_context(t.source_persona_id)->'families') f
      WHERE f->>'family_id' IN (SELECT family_id::text FROM public.family_member WHERE person_id=purge_test.id('P')));
  SELECT coalesce(array_agg((pk->>'id')::uuid ORDER BY (pk->>'id')::uuid),'{}') INTO v_new
    FROM private.person_purge_plan(purge_test.id('P')) WHERE sted='S48' AND tabel='private.source_persona_identity_candidate';
  IF cardinality(v_old)<2 OR v_new IS DISTINCT FROM v_old THEN
    RAISE EXCEPTION 'TEST_FAILED plan_s48_paritet';
  END IF;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
END $s48$;
\echo OK plan_s48_paritet
ROLLBACK;
\endif

-- =====================================================================================================================
-- Task 4: historik. Positive og negative kontroller; begge snapshots vurderes selvstændigt.
-- =====================================================================================================================
\if :g_historik
BEGIN;
CREATE TEMP TABLE hist ON COMMIT DROP AS SELECT * FROM private.person_purge_historik(purge_test.id('P'));
DO $t$
BEGIN
  IF (SELECT count(*) FROM public.change_event e JOIN hist h ON h.tabel='change_event' AND h.pk=jsonb_build_object('id',e.id)
      WHERE e.change_set_id=purge_test.id('saet_tidligere_slettet') AND e.tabel IN ('fact','relation','narrative','assertion','citation'))<>5 THEN
    RAISE EXCEPTION 'TEST_FAILED historik_tidligere_slettet';
  END IF;
END $t$;
\echo OK historik_tidligere_slettet
DO $t$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.change_event e JOIN hist h ON h.tabel='change_event' AND h.pk=jsonb_build_object('id',e.id)
      WHERE e.change_set_id=purge_test.id('saet_note_flyttet') AND e.tabel='note'
        AND e.foer->>'target_id'=purge_test.id('P')::text AND e.efter->>'target_id'<>purge_test.id('P')::text)
     OR NOT EXISTS (SELECT 1 FROM public.note WHERE id=purge_test.id('note_flyttet') AND target_id<>purge_test.id('P')) THEN
    RAISE EXCEPTION 'TEST_FAILED historik_flyttet_note';
  END IF;
END $t$;
\echo OK historik_flyttet_note
DO $t$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM hist WHERE tabel='change_set' AND pk=jsonb_build_object('id',purge_test.id('saet_withdraw')))
     OR EXISTS (SELECT 1 FROM public.change_event WHERE change_set_id=purge_test.id('saet_withdraw')) THEN
    RAISE EXCEPTION 'TEST_FAILED historik_withdraw_saet';
  END IF;
END $t$;
\echo OK historik_withdraw_saet
DO $t$
BEGIN
  IF EXISTS (SELECT 1 FROM hist WHERE tabel='change_set' AND pk=jsonb_build_object('id',purge_test.id('saet_fortryd_bevaret')))
     OR NOT EXISTS (SELECT 1 FROM hist WHERE tabel='change_set' AND pk=jsonb_build_object('id',purge_test.id('saet_fortryd_opret_P'))) THEN
    RAISE EXCEPTION 'TEST_FAILED historik_fortryd_bevaret';
  END IF;
END $t$;
\echo OK historik_fortryd_bevaret
DO $t$
BEGIN
  IF EXISTS (SELECT 1 FROM hist WHERE tabel='change_set' AND pk IN (
      jsonb_build_object('id',purge_test.id('faelles_saet')),jsonb_build_object('id',purge_test.id('saet_union_keep'))))
     OR NOT EXISTS (SELECT 1 FROM public.change_event e JOIN hist h ON h.tabel='change_event' AND h.pk=jsonb_build_object('id',e.id)
        WHERE e.change_set_id=purge_test.id('saet_union_keep'))
     OR NOT EXISTS (SELECT 1 FROM public.change_event e JOIN hist h ON h.tabel='change_event' AND h.pk=jsonb_build_object('id',e.id)
        WHERE e.change_set_id=purge_test.id('faelles_saet')) THEN
    RAISE EXCEPTION 'TEST_FAILED historik_faelles_bevaret';
  END IF;
END $t$;
\echo OK historik_faelles_bevaret

-- En tredje ændring på den allerede flyttede note er andens indhold; den må IKKE komme med via note-id'et.
DO $t$
DECLARE v_cs bigint;
BEGIN
  PERFORM purge_test.nyt();
  v_cs:=public.begin_change_set('purge_test_fremmed_note','Opdaterede note',NULL,NULL);
  UPDATE public.note SET indhold='Ny redaktionel note' WHERE id=purge_test.id('note_flyttet');
  IF EXISTS (SELECT 1 FROM public.change_event e JOIN private.person_purge_historik(purge_test.id('P')) h
    ON h.tabel='change_event' AND h.pk=jsonb_build_object('id',e.id) WHERE e.change_set_id=v_cs) THEN
    RAISE EXCEPTION 'TEST_FAILED historik_flyttet_note: fremmed efterfølgende event slettes';
  END IF;
END $t$;
\echo OK historik_flyttet_note_senere_bevaret
-- M*: et eksklusivt medie, som KUN findes i historikken, må med; et historisk delt medie skal bevares.
DO $t$
DECLARE v_ex bigint; v_shared bigint; v_rel bigint; v_cs bigint; v_ex_ev bigint; v_shared_ev bigint;
BEGIN
  v_ex:=nextval(pg_get_serial_sequence('public.media','id'));
  v_shared:=nextval(pg_get_serial_sequence('public.media','id'));
  PERFORM purge_test.nyt();
  v_cs:=public.begin_change_set('purge_test_historisk_medie','Historiske medier',NULL,NULL);
  v_ex_ev:=purge_test.hist_event(v_cs,1,'media','DELETE',to_jsonb(jsonb_populate_record(NULL::public.media,
    jsonb_build_object('id',v_ex,'titel','Historisk eksklusivt medie'))),NULL);
  v_shared_ev:=purge_test.hist_event(v_cs,2,'media','DELETE',to_jsonb(jsonb_populate_record(NULL::public.media,
    jsonb_build_object('id',v_shared,'titel','Historisk delt medie'))),NULL);
  v_rel:=nextval(pg_get_serial_sequence('public.relation','id'));
  PERFORM purge_test.hist_event(v_cs,3,'relation','DELETE',to_jsonb(jsonb_populate_record(NULL::public.relation,
    jsonb_build_object('id',v_rel,'subjekt_type','person','subjekt_id',purge_test.id('P'),'objekt_type','media','objekt_id',v_ex))),NULL);
  -- Samme relation-id flyttede fra P til tredje: relationens id alene beviser ikke eksklusivitet.
  v_rel:=nextval(pg_get_serial_sequence('public.relation','id'));
  PERFORM purge_test.hist_event(v_cs,4,'relation','UPDATE',to_jsonb(jsonb_populate_record(NULL::public.relation,
    jsonb_build_object('id',v_rel,'subjekt_type','person','subjekt_id',purge_test.id('P'),'objekt_type','media','objekt_id',v_shared))),
    to_jsonb(jsonb_populate_record(NULL::public.relation,
    jsonb_build_object('id',v_rel,'subjekt_type','person','subjekt_id',purge_test.id('tredje'),'objekt_type','media','objekt_id',v_shared))));
  IF NOT EXISTS (SELECT 1 FROM private.person_purge_historik(purge_test.id('P'))
        WHERE tabel='change_event' AND pk=jsonb_build_object('id',v_ex_ev))
     OR EXISTS (SELECT 1 FROM private.person_purge_historik(purge_test.id('P'))
        WHERE tabel='change_event' AND pk=jsonb_build_object('id',v_shared_ev)) THEN
    RAISE EXCEPTION 'TEST_FAILED historik_medie_kun_historik';
  END IF;
END $t$;
\echo OK historik_medie_kun_historik
ROLLBACK;
\endif

\if :g_fortrydelse
BEGIN;
-- Den eksisterende fixtur har en ægte C-batch med P og tredje. Den kan fortrydes nu;
-- efter planens event-fravalg står tredjes event tilbage og RPC'ens løkke kan fortsat køre.
-- Der slettes ingen append-only-rækker i Task 4. Efter-tilstanden testes som et læst fravalg.
DO $t$
DECLARE v_b uuid:=purge_test.u('c_batch'); v_a uuid; v_res jsonb; v_error text; v_n bigint; v_remaining bigint;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','a2a00000-0000-4000-8000-00000000a001',true);
  PERFORM purge_test.nyt();
  SELECT count(*) INTO v_n FROM private.reimport_event WHERE batch_id=v_b AND operation='publication_identity';
  SELECT count(*) INTO v_remaining FROM private.reimport_event e WHERE batch_id=v_b AND operation='publication_identity'
    AND NOT EXISTS (SELECT 1 FROM private.person_purge_plan(purge_test.id('P')) q
      WHERE q.tabel='private.reimport_event' AND q.handling='slet' AND q.pk=jsonb_build_object('id',e.id));
  IF v_n<>2 OR v_remaining<>1 OR EXISTS (
    SELECT 1 FROM private.reimport_event e JOIN private.source_persona_identity i ON i.source_persona_id::text=e.payload->>'source_persona_id'
    WHERE e.batch_id=v_b AND e.canonical_person_id IS DISTINCT FROM purge_test.id('P')
      AND i.version IS DISTINCT FROM (e.payload#>>'{result_receipt,identity_version}')::integer) THEN
    RAISE EXCEPTION 'TEST_FAILED fortrydelse_publication: fixture/prædikat';
  END IF;
  -- Prøv den rigtige RPC nu og rul dens ændringer tilbage via en lokal subtransaktion.
  BEGIN
    SET LOCAL ROLE service_role;
    v_a:=public.red_authorize_reimport_reversal(v_b,gen_random_uuid(),clock_timestamp()+interval '10 minutes');
    SET LOCAL ROLE authenticated;
    v_res:=public.red_reverse_reimport_publication(v_b,v_a);
    RESET ROLE;
    IF v_res->>'status' IS DISTINCT FROM 'reversed' OR (v_res->>'reversed_identities')::int<>2 THEN
      RAISE EXCEPTION 'TEST_FAILED fortrydelse_publication: forkert kvittering';
    END IF;
    SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
    RAISE SQLSTATE 'ZX001'; -- rollback af den vellykkede prøve; IKKE en produktionsfejl
  EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL;
  END;
  IF (SELECT status FROM private.reimport_batch WHERE id=v_b) IS DISTINCT FROM 'finalized' THEN
    RAISE EXCEPTION 'TEST_FAILED fortrydelse_publication: prøve blev ikke rullet tilbage';
  END IF;
  -- Name-completion-fixturen er bevidst en S42-tilnærmelse: ingen activation-kvittering og forkert result-hash.
  -- Den må IKKE tælles som et tab af en i dag fungerende fortrydelse. Begge navne rammer samme gate.
  v_b:=purge_test.u('nc_forælder');
  SET LOCAL ROLE service_role;
  v_a:=public.red_authorize_reimport_reversal(v_b,gen_random_uuid(),clock_timestamp()+interval '10 minutes');
  RESET ROLE;
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM public.red_reverse_reimport(v_b,v_a);
    RESET ROLE;
    RAISE EXCEPTION 'TEST_FAILED fortrydelse_reimport: syntetisk batch blev accepteret';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    IF v_error IS DISTINCT FROM 'REIMPORT_WRITER_REVERSAL_INVALID' THEN RAISE; END IF;
  END;
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM public.red_reverse_1939_v50_reimport(v_b,v_a);
    RESET ROLE;
    RAISE EXCEPTION 'TEST_FAILED fortrydelse_wrapper: syntetisk batch blev accepteret';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    IF v_error IS DISTINCT FROM 'REIMPORT_1939_REVERSAL_INVALID' THEN RAISE; END IF;
  END;
  -- Kontrakt v2 tilbagekalder authenticated-EXECUTE på C3-vejen (apply_narrative_record_contract_acl).
  -- Bevis både den faktiske klientgrænse og den fortsatte kontraktport for ejerkald; ingen GRANT til testen.
  IF has_function_privilege('authenticated','public.red_reverse_reimport_cases(uuid,uuid)','EXECUTE') THEN
    RAISE EXCEPTION 'TEST_FAILED fortrydelse_cases: authenticated har EXECUTE under kontrakt 2';
  END IF;
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM public.red_reverse_reimport_cases(gen_random_uuid(),gen_random_uuid());
    RESET ROLE;
    RAISE EXCEPTION 'TEST_FAILED fortrydelse_cases: klientkald blev accepteret';
  EXCEPTION WHEN insufficient_privilege THEN NULL; -- præcis SQLSTATE 42501; andre fejl får testen til at fejle
  END;
  BEGIN
    -- Ejerrollen er gendannet af subtransaktionens rollback efter ACL-afvisningen ovenfor.
    PERFORM public.red_reverse_reimport_cases(gen_random_uuid(),gen_random_uuid());
    RAISE EXCEPTION 'TEST_FAILED fortrydelse_cases: ejerens kontrakt-2-port accepterede';
  EXCEPTION WHEN raise_exception THEN
    GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
    IF v_error IS DISTINCT FROM 'NARRATIVE_RECORD_LEGACY_WRITER_DISABLED' THEN RAISE; END IF;
  END;
END $t$;
\echo OK fortrydelse_publication
\echo OK fortrydelse_reimport
\echo OK fortrydelse_wrapper
\echo OK fortrydelse_cases
ROLLBACK;
-- Test samme eksekverbare prædikater som målingen. UUID'er forbliver i sessionsvariabler.
BEGIN;
\set purge_reversal_assert on
CREATE FUNCTION pg_temp.assert_reversal(p_counts bigint[],p_expected_counts bigint[],p_batches jsonb,
  p_generic_ready uuid[],p_generic_lost uuid[],p_publication_ready uuid[],p_publication_lost uuid[])
RETURNS void LANGUAGE plpgsql AS $assert$
BEGIN
  IF p_counts IS DISTINCT FROM p_expected_counts OR p_batches IS DISTINCT FROM jsonb_build_object(
    'generic_ready',to_jsonb(p_generic_ready),'generic_lost',to_jsonb(p_generic_lost),
    'publication_ready',to_jsonb(p_publication_ready),'publication_lost',to_jsonb(p_publication_lost)) THEN
    RAISE EXCEPTION 'TEST_FAILED fortrydelse_praedikater: antal/batchmængder';
  END IF;
END $assert$;
SELECT purge_test.id('P') AS pid \gset
\ir person-purge-reversal-count.sql
SELECT pg_temp.assert_reversal(
  ARRAY[:reversal_reimport_kan_nu,:reversal_reimport_mistes,:reversal_wrapper_kan_nu,:reversal_wrapper_mistes,
        :reversal_cases_kan_nu,:reversal_cases_mistes,:reversal_publication_kan_nu,:reversal_publication_mistes]::bigint[],
  ARRAY[0,0,0,0,0,0,1,1]::bigint[],:'reversal_batches'::jsonb,
  '{}'::uuid[],'{}'::uuid[],ARRAY[purge_test.u('c_batch')],ARRAY[purge_test.u('c_batch')]);
\echo OK fortrydelse_praedikater_fixture

\ir fixtures/person-purge-reimport.sql
CREATE TEMP TABLE generic_test(state jsonb NOT NULL,haendelse_id bigint NOT NULL) ON COMMIT DROP;
DO $setup$
DECLARE v_source bigint:=nextval(pg_get_serial_sequence('public.source','id')); v_state jsonb;
  v_narr bigint; v_h bigint; v_auth uuid; v_result jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','a2a00000-0000-4000-8000-00000000a001',true);
  PERFORM purge_test.nyt();
  v_state:=pg_temp.purge_stage_profile(v_source,'purge-generic','PURGE-GENERIC-Q',
    'Purge Q',v_source);
  v_state:=pg_temp.purge_complete_profile(v_state);
  SELECT np.narrative_id INTO STRICT v_narr FROM private.narrative_record_publication np
    WHERE np.source_record_id=(v_state->>'source_record_id')::uuid AND np.status='draft';
  -- Præcis én hændelse: subjekt P, narrativ Q. Receiptet skal fødes MED has_haendelse=true.
  PERFORM purge_test.nyt();
  INSERT INTO public.haendelse(subjekt_type,subjekt_id,narrative_id,noegle,klausul)
    VALUES ('person',purge_test.id('P'),v_narr,'purge-generic-s26','Syntetisk hændelse') RETURNING id INTO v_h;
  v_auth:=public.red_authorize_reimport_cutover((v_state->>'source_batch_id')::uuid,gen_random_uuid(),clock_timestamp()+interval '10 minutes');
  v_result:=public.red_activate_reimport_batch((v_state->>'source_batch_id')::uuid,v_auth);
  IF v_result->>'status' IS DISTINCT FROM 'activated' THEN
    RAISE EXCEPTION 'TEST_FAILED fortrydelse_generel_setup';
  END IF;
  PERFORM purge_test.nyt();
  INSERT INTO generic_test VALUES (v_state,v_h);
  IF (SELECT count(*) FROM public.haendelse WHERE narrative_id=v_narr)<>1
    OR NOT EXISTS (SELECT 1 FROM private.person_purge_plan(purge_test.id('P'))
      WHERE tabel='haendelse' AND pk=jsonb_build_object('id',v_h) AND sted='S26' AND handling='slet')
    OR EXISTS (SELECT 1 FROM private.person_purge_plan(purge_test.id('P')) q WHERE q.handling<>'bevar_andres' AND (
      (q.tabel='narrative' AND q.pk=jsonb_build_object('id',v_narr))
      OR (q.tabel='private.source_persona_identity' AND q.pk->>'source_persona_id'=v_state->>'source_persona_id')
      OR (q.tabel='private.reimport_event' AND EXISTS (SELECT 1 FROM private.reimport_event e
        WHERE q.pk=jsonb_build_object('id',e.id) AND e.batch_id IN ((v_state->>'source_batch_id')::uuid,(v_state->>'child_batch_id')::uuid))))) THEN
    RAISE EXCEPTION 'TEST_FAILED fortrydelse_s26: kun indirekte påvirkning kræves';
  END IF;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
END $setup$;

-- Positiv kontrol: både den generelle RPC og wrapperen gennemfører FØR S26 fjernes.
DO $positive$
DECLARE v_b uuid; v_auth uuid; v_result jsonb; v_wrapper boolean;
BEGIN
  SELECT (state->>'source_batch_id')::uuid INTO STRICT v_b FROM generic_test;
  FOREACH v_wrapper IN ARRAY ARRAY[false,true] LOOP
    BEGIN
      PERFORM purge_test.nyt();
      SET LOCAL ROLE service_role;
      v_auth:=public.red_authorize_reimport_reversal(v_b,gen_random_uuid(),clock_timestamp()+interval '10 minutes');
      SET LOCAL ROLE authenticated;
      IF v_wrapper THEN v_result:=public.red_reverse_1939_v50_reimport(v_b,v_auth);
      ELSE v_result:=public.red_reverse_reimport(v_b,v_auth); END IF;
      RESET ROLE;
      IF v_result->>'status' IS DISTINCT FROM 'reversed' THEN
        RAISE EXCEPTION 'TEST_FAILED fortrydelse_generel_positiv';
      END IF;
      SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
      RAISE SQLSTATE 'ZX001';
    EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL;
    END;
    IF (SELECT status FROM private.reimport_batch WHERE id=v_b) IS DISTINCT FROM 'activated' THEN
      RAISE EXCEPTION 'TEST_FAILED fortrydelse_generel_positiv: rollback';
    END IF;
  END LOOP;
END $positive$;
\echo OK fortrydelse_generel_positiv

-- S26 skal advare for netop Q's batch ved begge API-navne; C-fixturen skal stadig være med.
SELECT purge_test.id('P') AS pid \gset
\ir person-purge-reversal-count.sql
SELECT pg_temp.assert_reversal(
  ARRAY[:reversal_reimport_kan_nu,:reversal_reimport_mistes,:reversal_wrapper_kan_nu,:reversal_wrapper_mistes,
        :reversal_cases_kan_nu,:reversal_cases_mistes,:reversal_publication_kan_nu,:reversal_publication_mistes]::bigint[],
  ARRAY[1,1,1,1,0,0,1,1]::bigint[],:'reversal_batches'::jsonb,
  ARRAY[(state->>'source_batch_id')::uuid],ARRAY[(state->>'source_batch_id')::uuid],
  ARRAY[purge_test.u('c_batch')],ARRAY[purge_test.u('c_batch')]) FROM generic_test;
\echo OK fortrydelse_s26_advarsel

-- Negativ kontrol: en uberørt person må ikke give blanketadvarsel for Q eller C-batchen.
SELECT purge_test.id('nabo') AS pid \gset
\ir person-purge-reversal-count.sql
SELECT pg_temp.assert_reversal(
  ARRAY[:reversal_reimport_kan_nu,:reversal_reimport_mistes,:reversal_wrapper_kan_nu,:reversal_wrapper_mistes,
        :reversal_cases_kan_nu,:reversal_cases_mistes,:reversal_publication_kan_nu,:reversal_publication_mistes]::bigint[],
  ARRAY[1,0,1,0,0,0,1,0]::bigint[],:'reversal_batches'::jsonb,
  ARRAY[(state->>'source_batch_id')::uuid],'{}'::uuid[],ARRAY[purge_test.u('c_batch')],'{}'::uuid[]) FROM generic_test;
\echo OK fortrydelse_uberoert

DO $s26_drift$
DECLARE v_state jsonb; v_b uuid; v_before jsonb; v_after jsonb; v_receipt jsonb; v_auth uuid; v_error text;
  v_wrapper boolean;
BEGIN
  SELECT state,(state->>'source_batch_id')::uuid INTO STRICT v_state,v_b FROM generic_test;
  v_before:=private.narrative_record_state((v_state->>'person_id')::bigint,(v_state->>'source_id')::bigint,
    v_state->'person_payload'->>'source_record_key',false);
  SELECT payload->'post_activation_receipts'->(v_state->>'person_id') INTO STRICT v_receipt
    FROM private.reimport_event WHERE batch_id=v_b AND operation='activation';
  PERFORM purge_test.nyt();
  DELETE FROM public.haendelse WHERE id=(SELECT haendelse_id FROM generic_test);
  v_after:=private.narrative_record_state((v_state->>'person_id')::bigint,(v_state->>'source_id')::bigint,
    v_state->'person_payload'->>'source_record_key',false);
  IF v_before#>>'{publication_state,narrative,has_haendelse}' IS DISTINCT FROM 'true'
    OR v_after#>>'{publication_state,narrative,has_haendelse}' IS DISTINCT FROM 'false'
    OR v_before->>'state_sha256' IS DISTINCT FROM v_receipt->>'state_sha256'
    OR v_after->>'state_sha256' IS NOT DISTINCT FROM v_receipt->>'state_sha256' THEN
    RAISE EXCEPTION 'TEST_FAILED fortrydelse_s26: receipt-drift';
  END IF;
  FOREACH v_wrapper IN ARRAY ARRAY[false,true] LOOP
    PERFORM purge_test.nyt();
    SET LOCAL ROLE service_role;
    v_auth:=public.red_authorize_reimport_reversal(v_b,gen_random_uuid(),clock_timestamp()+interval '10 minutes');
    RESET ROLE;
    BEGIN
      SET LOCAL ROLE authenticated;
      IF v_wrapper THEN PERFORM public.red_reverse_1939_v50_reimport(v_b,v_auth);
      ELSE PERFORM public.red_reverse_reimport(v_b,v_auth); END IF;
      RESET ROLE;
      RAISE EXCEPTION 'TEST_FAILED fortrydelse_s26: ugyldigt receipt accepteret';
    EXCEPTION WHEN raise_exception THEN
      GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
      IF v_error IS DISTINCT FROM (CASE WHEN v_wrapper THEN 'REIMPORT_1939_REVERSAL_INVALID'
        ELSE 'REIMPORT_WRITER_REVERSAL_INVALID' END) THEN RAISE; END IF;
    END;
  END LOOP;
END $s26_drift$;
\echo OK fortrydelse_s26_receipt_drift
\unset purge_reversal_assert
ROLLBACK;
\endif


-- =====================================================================================================================
-- Gruppe manifest (Task 5). Alle negative DML-tests kræver den oprindelige append-only-fejl; andre fejl tæller ikke.
-- Kun den afsluttende positive kandidatsletning COMMIT'er. Resten isoleres i transaktioner/subtransaktioner.
-- =====================================================================================================================
\if :g_manifest
CREATE FUNCTION pg_temp.append_fejl(p_tabel text, p_op text DEFAULT 'DELETE') RETURNS text
LANGUAGE sql AS $$
  SELECT CASE p_tabel
    WHEN 'private.reimport_event' THEN 'REIMPORT_EVENT_APPEND_ONLY'
    WHEN 'private.reimport_name_completion_result' THEN 'REIMPORT_NAME_COMPLETION_RESULT_APPEND_ONLY'
    WHEN 'private.reimport_case_event' THEN 'REIMPORT_CASE_EVENT_APPEND_ONLY'
    WHEN 'private.narrative_publication_event' THEN 'NARRATIVE_PUBLICATION_EVENT_APPEND_ONLY'
    ELSE 'EVIDENCE_APPEND_ONLY: '||p_tabel||' kan ikke '||p_op END
$$;
CREATE FUNCTION pg_temp.afvis(p_sql text, p_error text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_error text;
BEGIN
  BEGIN EXECUTE p_sql; EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM; END;
  IF v_error IS DISTINCT FROM p_error THEN
    RAISE EXCEPTION 'TEST_FAILED manifest: forventet %, fik %',p_error,v_error;
  END IF;
END $$;
-- PK fra fixturens uafhængige facit; kræv også en faktisk række før DML (ellers ville DELETE af nul rækker bestå).
CREATE FUNCTION pg_temp.slet_sql(p_tabel text, p_pk jsonb) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v_n bigint;
BEGIN
  EXECUTE format('SELECT count(*) FROM %s t WHERE to_jsonb(t) @> $1',p_tabel) INTO v_n USING p_pk;
  IF v_n<>1 THEN RAISE EXCEPTION 'TEST_FAILED manifest: forventet 1 række i %, fik %',p_tabel,v_n; END IF;
  RETURN format('DELETE FROM %s t WHERE to_jsonb(t) @> %L::jsonb',p_tabel,p_pk);
END $$;

BEGIN;
DO $t$
DECLARE r record;
BEGIN
  FOR r IN SELECT DISTINCT ON (f.tabel) f.tabel,f.pk FROM purge_test.forventet f
    WHERE f.tabel IN (SELECT tabel FROM private.person_purge_tilladte_tabeller()) ORDER BY f.tabel,f.pk LOOP
    PERFORM pg_temp.afvis(pg_temp.slet_sql(r.tabel,r.pk),pg_temp.append_fejl(r.tabel));
  END LOOP;
  IF (SELECT count(DISTINCT f.tabel) FROM purge_test.forventet f
      WHERE f.tabel IN (SELECT tabel FROM private.person_purge_tilladte_tabeller()))<>12 THEN
    RAISE EXCEPTION 'TEST_FAILED manifest: alle 12 tabeller skal have en eksisterende fixturrække';
  END IF;
END $t$;
ROLLBACK;
\echo OK manifest_uden_raekke_afvises
\echo OK afvisningstekst_uaendret



BEGIN;
DO $t$
DECLARE v_pk jsonb; v_sql text; v_t text:='private.source_persona_identity_event';
BEGIN
  SELECT jsonb_build_object('id',id) INTO STRICT v_pk FROM private.source_persona_identity_event
   WHERE source_persona_id=purge_test.u('X2') AND version=3;
  v_sql:=pg_temp.slet_sql(v_t,v_pk);
  INSERT INTO private.person_purge_manifest VALUES
    (pg_current_xact_id(),pg_backend_pid(),purge_test.id('tredje'),v_t,v_pk,'egen',NULL);
  PERFORM pg_temp.afvis(v_sql,pg_temp.append_fejl(v_t));
  UPDATE private.person_purge_manifest SET person_id=purge_test.id('P'),backend_pid=pg_backend_pid()+1;
  PERFORM pg_temp.afvis(v_sql,pg_temp.append_fejl(v_t));
  -- Samme backend, men en afsluttet transaktions manifest må heller ikke autorisere.
  UPDATE private.person_purge_manifest SET backend_pid=pg_backend_pid(),xid='1'::xid8;
  PERFORM pg_temp.afvis(v_sql,pg_temp.append_fejl(v_t));
  UPDATE private.person_purge_manifest SET xid=pg_current_xact_id();
  -- Positiv kontrol på præcis den samme række viser, at afvisningerne skyldtes gates ovenfor.
  EXECUTE v_sql;
END $t$;
ROLLBACK;
\echo OK manifest_anden_person_afvises
\echo OK manifest_anden_backend
\echo OK manifest_anden_transaktion

BEGIN;
DO $t$
DECLARE v_pk jsonb; v_other jsonb; v_t text:='private.source_persona_identity_event';
BEGIN
  SELECT jsonb_build_object('id',id) INTO STRICT v_pk FROM private.source_persona_identity_event
   WHERE source_persona_id=purge_test.u('X2') AND version=3;
  SELECT jsonb_build_object('id',id) INTO STRICT v_other FROM private.source_persona_identity_event
   WHERE source_persona_id=purge_test.u('X1') AND version=1;
  INSERT INTO private.person_purge_manifest VALUES
    (pg_current_xact_id(),pg_backend_pid(),purge_test.id('P'),v_t,v_other,'egen',NULL);
  PERFORM pg_temp.afvis(pg_temp.slet_sql(v_t,v_pk),pg_temp.append_fejl(v_t));
  UPDATE private.person_purge_manifest SET pk=v_pk;
  EXECUTE pg_temp.slet_sql(v_t,v_pk);
END $t$;
ROLLBACK;
\echo OK manifest_kraever_praecis_pk

-- Fuld JSONB-lighed: hver probe har en rigtig række, gyldig grund og korrekt ejer.
-- {} og delvis PK fanger containment i den ene retning; ekstra felt fanger den modsatte.
BEGIN;
DO $t$
DECLARE v_pk jsonb; v_bad_pk jsonb; v_sql text; v_t text:='private.reimport_event';
BEGIN
  SELECT jsonb_build_object('id',id) INTO STRICT v_pk FROM private.reimport_event
    WHERE canonical_person_id=purge_test.id('P') ORDER BY id LIMIT 1;
  v_sql:=pg_temp.slet_sql(v_t,v_pk);
  INSERT INTO private.person_purge_manifest VALUES
    (pg_current_xact_id(),pg_backend_pid(),purge_test.id('P'),v_t,v_pk,'egen',NULL);
  IF private.person_purge_tilladt(v_t,v_pk||jsonb_build_object('canonical_person_id',purge_test.id('P'))) IS NOT TRUE THEN
    RAISE EXCEPTION 'TEST_FAILED manifest_pk_prober: positiv kontrol';
  END IF;
  FOR v_bad_pk IN SELECT pk FROM (VALUES
    ('{}'::jsonb),
    (v_pk||jsonb_build_object('ekstra',true)),
    (jsonb_build_object('id',v_pk->>'id'))
  ) bad(pk) LOOP
    UPDATE private.person_purge_manifest SET pk=v_bad_pk WHERE tabel=v_t;
    PERFORM pg_temp.afvis(v_sql,pg_temp.append_fejl(v_t));
  END LOOP;

  v_t:='private.legacy_placement_disposition';
  SELECT jsonb_build_object('person_id',person_id,'source_id',source_id,'version',version) INTO STRICT v_pk
    FROM private.legacy_placement_disposition WHERE person_id=purge_test.id('P') ORDER BY source_id,version LIMIT 1;
  INSERT INTO private.person_purge_manifest VALUES
    (pg_current_xact_id(),pg_backend_pid(),purge_test.id('P'),v_t,v_pk,'egen',NULL);
  IF private.person_purge_tilladt(v_t,v_pk) IS NOT TRUE THEN
    RAISE EXCEPTION 'TEST_FAILED manifest_pk_prober: positiv kontrol sammensat PK';
  END IF;
  UPDATE private.person_purge_manifest SET pk=jsonb_build_object('person_id',v_pk->'person_id') WHERE tabel=v_t;
  PERFORM pg_temp.afvis(pg_temp.slet_sql(v_t,v_pk),pg_temp.append_fejl(v_t));
END $t$;
ROLLBACK;
\echo OK manifest_pk_tom_ekstra_og_forkert_type_afvises
\echo OK manifest_pk_delvis_sammensat_afvises

BEGIN;
DO $t$
DECLARE v_pk jsonb; v_t text:='private.source_persona_identity_event';
BEGIN
  SELECT jsonb_build_object('id',id) INTO STRICT v_pk FROM private.source_persona_identity_event
   WHERE source_persona_id=purge_test.u('X2') AND version=1;
  INSERT INTO private.person_purge_manifest VALUES
    (pg_current_xact_id(),pg_backend_pid(),purge_test.id('P'),v_t,v_pk,'egen',NULL);
  PERFORM pg_temp.afvis(pg_temp.slet_sql(v_t,v_pk),pg_temp.append_fejl(v_t));
END $t$;
ROLLBACK;
\echo OK manifest_forkert_grund

-- Manifest fra den eksisterende plan, men state-kvitteringens PK normaliseres til dens faktiske primærnøgle.
-- Task 4's plan bærer også canonical_person_id i state-pk til sin driftkontrol; Task 6-kontrakten bruger kun persona.
CREATE FUNCTION pg_temp.manifest() RETURNS void LANGUAGE sql AS $$
  INSERT INTO private.person_purge_manifest(xid,backend_pid,person_id,tabel,pk,grund,forrige_version)
  SELECT pg_current_xact_id(),pg_backend_pid(),purge_test.id('P'),tabel,
    CASE WHEN tabel='private.source_persona_identity' THEN jsonb_build_object('source_persona_id',pk->'source_persona_id') ELSE pk END,
    grund,(ekstra->>'forrige_version')::int
  FROM private.person_purge_plan(purge_test.id('P')) WHERE handling='slet' AND grund IS NOT NULL
$$;

-- Negativt ejerskab på ALLE 12 tabeller og begge afstemningsveje, med rigtige fixturrækker.
-- Her spiller fixturens P rollen Q (rækkernes ejer), og tredje spiller sletningens P.
-- Kun målpostens person ændres; afledte poster beholder den korrekte ejers referenceposter.
BEGIN;
DO $t$ BEGIN PERFORM pg_temp.manifest(); END $t$;
DO $t$
DECLARE r record; v_old jsonb; v_antal int:=0;
BEGIN
  FOR r IN SELECT m.tabel,m.pk,m.person_id FROM private.person_purge_manifest m
    WHERE m.tabel IN (SELECT tabel FROM private.person_purge_tilladte_tabeller()) ORDER BY m.tabel,m.pk LOOP
    EXECUTE format('SELECT to_jsonb(t) FROM %s t WHERE to_jsonb(t) @> $1',r.tabel) INTO STRICT v_old USING r.pk;
    IF private.person_purge_tilladt(r.tabel,v_old) IS NOT TRUE THEN
      RAISE EXCEPTION 'TEST_FAILED manifest_anden_ejer: positiv kontrol i %',r.tabel;
    END IF;
    UPDATE private.person_purge_manifest SET person_id=purge_test.id('tredje') WHERE tabel=r.tabel AND pk=r.pk;
    IF private.person_purge_tilladt(r.tabel,v_old) IS DISTINCT FROM false THEN
      RAISE EXCEPTION 'TEST_FAILED manifest_anden_ejer: fremmed række tilladt i %',r.tabel;
    END IF;
    PERFORM pg_temp.afvis(pg_temp.slet_sql(r.tabel,r.pk),pg_temp.append_fejl(r.tabel));
    UPDATE private.person_purge_manifest SET person_id=r.person_id WHERE tabel=r.tabel AND pk=r.pk;
    v_antal:=v_antal+1;
  END LOOP;
  IF (SELECT count(DISTINCT m.tabel) FROM private.person_purge_manifest m
       WHERE m.tabel IN (SELECT tabel FROM private.person_purge_tilladte_tabeller()))<>12
     OR (SELECT count(*) FROM private.person_purge_manifest WHERE tabel='private.text_revision_reconciliation')<>2
     OR v_antal<13 THEN
    RAISE EXCEPTION 'TEST_FAILED manifest_anden_ejer: manglende tabel/afstemningsvej';
  END IF;
END $t$;
ROLLBACK;
\echo OK manifest_anden_ejer_alle_tabeller

BEGIN;
DO $t$ BEGIN PERFORM pg_temp.manifest(); END $t$;
DELETE FROM private.person_purge_manifest WHERE tabel='private.source_persona_identity';
DO $t$
DECLARE r record; v_n int:=0;
BEGIN
  FOR r IN SELECT id FROM private.source_persona_identity_event WHERE source_persona_id=purge_test.u('X2') LOOP
    v_n:=v_n+1;
    PERFORM pg_temp.afvis(pg_temp.slet_sql('private.source_persona_identity_event',jsonb_build_object('id',r.id)),
                         pg_temp.append_fejl('private.source_persona_identity_event'));
  END LOOP;
  IF v_n<>3 THEN RAISE EXCEPTION 'TEST_FAILED hel_stroem_kraever_statekvittering'; END IF;
END $t$;
ROLLBACK;
\echo OK hel_stroem_kraever_statekvittering

BEGIN;
DO $t$ BEGIN PERFORM pg_temp.manifest(); END $t$;
-- State opdateres som ejer i testens rollback; eventstrøm og kvittering står uændret.
UPDATE private.source_persona_identity SET canonical_person_id=purge_test.id('tredje')
 WHERE source_persona_id=purge_test.u('X2');
DO $t$
DECLARE r record; v_n int:=0;
BEGIN
  FOR r IN SELECT id FROM private.source_persona_identity_event WHERE source_persona_id=purge_test.u('X2') LOOP
    v_n:=v_n+1;
    PERFORM pg_temp.afvis(pg_temp.slet_sql('private.source_persona_identity_event',jsonb_build_object('id',r.id)),
                         pg_temp.append_fejl('private.source_persona_identity_event'));
  END LOOP;
  IF v_n<>3 THEN RAISE EXCEPTION 'TEST_FAILED hel_stroem_kraever_gaeldende_person'; END IF;
END $t$;
ROLLBACK;
\echo OK hel_stroem_kraever_gaeldende_person

BEGIN;
DO $t$ BEGIN PERFORM pg_temp.manifest(); END $t$;
DO $t$
DECLARE v_n int;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM private.source_persona_identity_event WHERE source_persona_id=purge_test.u('X2')
                 AND canonical_person_id IS NULL)
     OR NOT EXISTS (SELECT 1 FROM private.source_persona_identity_event WHERE source_persona_id=purge_test.u('X2')
                    AND canonical_person_id=purge_test.id('tredje')) THEN
    RAISE EXCEPTION 'TEST_FAILED hel_stroem: manglende negativt/andens event';
  END IF;
  DELETE FROM private.source_persona_identity_event WHERE source_persona_id=purge_test.u('X2');
  GET DIAGNOSTICS v_n=ROW_COUNT;
  IF v_n<>3 THEN RAISE EXCEPTION 'TEST_FAILED hel_stroem_tillader_null_og_anden'; END IF;
END $t$;
ROLLBACK;
\echo OK hel_stroem_tillader_null_og_anden

BEGIN;
DO $t$ BEGIN PERFORM pg_temp.manifest(); END $t$;
CREATE TEMP TABLE sletteorden(n int GENERATED ALWAYS AS IDENTITY, version int);
CREATE FUNCTION pg_temp.sletteorden() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN INSERT INTO sletteorden(version) VALUES(OLD.version); RETURN OLD; END $$;
CREATE TRIGGER zz_purge_test_orden BEFORE DELETE ON private.source_persona_identity_event
 FOR EACH ROW EXECUTE FUNCTION pg_temp.sletteorden();
-- CLUSTER i testkopien gør heap-rækkefølgen faldende; tving seqscan og kontrollér den observerede rækkefølge.
CREATE INDEX purge_test_version_desc ON private.source_persona_identity_event(version DESC);
CLUSTER private.source_persona_identity_event USING purge_test_version_desc;
SET LOCAL enable_indexscan=off;
SET LOCAL enable_bitmapscan=off;
DELETE FROM private.source_persona_identity_event WHERE source_persona_id=purge_test.u('X2');
DO $t$
BEGIN
  IF (SELECT array_agg(version ORDER BY n) FROM sletteorden) IS DISTINCT FROM ARRAY[3,2,1] THEN
    RAISE EXCEPTION 'TEST_FAILED hel_stroem_faldende_orden: ét DELETE observerede ikke 3,2,1';
  END IF;
END $t$;
ROLLBACK;
BEGIN;
DO $t$ BEGIN PERFORM pg_temp.manifest(); END $t$;
DO $t$
DECLARE v int; v_n int;
BEGIN
  FOR v IN REVERSE 3..1 LOOP
    DELETE FROM private.source_persona_identity_event WHERE source_persona_id=purge_test.u('X2') AND version=v;
    GET DIAGNOSTICS v_n=ROW_COUNT;
    IF v_n<>1 THEN RAISE EXCEPTION 'TEST_FAILED hel_stroem_faldende_orden: tre DELETE'; END IF;
  END LOOP;
END $t$;
ROLLBACK;
BEGIN;
DO $t$ BEGIN PERFORM pg_temp.manifest(); END $t$;
UPDATE private.person_purge_manifest SET forrige_version=2 WHERE tabel='private.source_persona_identity';
DO $t$
DECLARE r record;
BEGIN
  FOR r IN SELECT id FROM private.source_persona_identity_event WHERE source_persona_id=purge_test.u('X2') LOOP
    PERFORM pg_temp.afvis(pg_temp.slet_sql('private.source_persona_identity_event',jsonb_build_object('id',r.id)),
                         pg_temp.append_fejl('private.source_persona_identity_event'));
  END LOOP;
END $t$;
ROLLBACK;
\echo OK hel_stroem_faldende_orden

BEGIN;
DO $t$
DECLARE v_t text; v_pk jsonb;
BEGIN
  FOREACH v_t IN ARRAY ARRAY['private.source_record','private.interpretation'] LOOP
    EXECUTE format('SELECT jsonb_build_object(''id'',id) FROM %s ORDER BY id LIMIT 1',v_t) INTO STRICT v_pk;
    INSERT INTO private.person_purge_manifest VALUES
      (pg_current_xact_id(),pg_backend_pid(),purge_test.id('P'),v_t,v_pk,'egen',NULL);
    PERFORM pg_temp.afvis(pg_temp.slet_sql(v_t,v_pk),pg_temp.append_fejl(v_t));
  END LOOP;
END $t$;
ROLLBACK;
\echo OK bogtabel_altid_afvist

BEGIN;
DO $t$ BEGIN PERFORM pg_temp.manifest(); END $t$;
UPDATE private.person_purge_manifest SET grund='ukendt';
DO $t$
DECLARE r record;
BEGIN
  FOR r IN SELECT DISTINCT ON (m.tabel) m.tabel,m.pk FROM private.person_purge_manifest m
     WHERE m.tabel IN (SELECT tabel FROM private.person_purge_tilladte_tabeller()) ORDER BY m.tabel,m.pk LOOP
    PERFORM pg_temp.afvis(pg_temp.slet_sql(r.tabel,r.pk),pg_temp.append_fejl(r.tabel));
  END LOOP;
END $t$;
ROLLBACK;
\echo OK manifest_ukendt_grund_alle_tabeller

BEGIN;
DO $t$ BEGIN PERFORM pg_temp.manifest(); END $t$;
DO $t$
DECLARE r record; v_n int; v_kolonne name; v_update_antal int:=0;
BEGIN
  -- UPDATE skal ramme en rigtig manifesteret række i hver af de 12 tabeller og bevare den præcise fejl.
  FOR r IN SELECT DISTINCT ON (m.tabel) m.tabel,m.pk FROM private.person_purge_manifest m
     WHERE m.tabel IN (SELECT tabel FROM private.person_purge_tilladte_tabeller()) ORDER BY m.tabel,m.pk LOOP
    PERFORM pg_temp.slet_sql(r.tabel,r.pk);
    -- GENERATED ALWAYS kan afvise SET id=id før rækketriggeren. Brug den første almindelige kolonne uden for PK.
    SELECT a.attname INTO v_kolonne FROM pg_attribute a
     WHERE a.attrelid=to_regclass(r.tabel) AND a.attnum>0 AND NOT a.attisdropped
       AND a.attidentity='' AND a.attgenerated=''
       AND NOT EXISTS (SELECT 1 FROM pg_index i WHERE i.indrelid=a.attrelid AND i.indisprimary
                        AND a.attnum=ANY(i.indkey))
     ORDER BY a.attnum LIMIT 1;
    IF NOT FOUND THEN
      RAISE EXCEPTION 'TEST_FAILED update_uaendret_forbudt: ingen almindelig kolonne uden for PK i %',r.tabel;
    END IF;
    PERFORM pg_temp.afvis(format('UPDATE %s t SET %I=%I WHERE to_jsonb(t) @> %L::jsonb',
      r.tabel,v_kolonne,v_kolonne,r.pk),pg_temp.append_fejl(r.tabel,'UPDATE'));
    v_update_antal:=v_update_antal+1;
  END LOOP;
  IF v_update_antal<>12 THEN
    RAISE EXCEPTION 'TEST_FAILED update_uaendret_forbudt: forventet 12 tabeller, fik %',v_update_antal;
  END IF;
  -- En positiv sletning fra hver tabel (i subtransaktion, så FK-forældre og fixturen bevares).
  -- Disse tests er også følsomme for manglende tilladelser til en enkelt grund/tabel.
  UPDATE private.narrative_legacy_publication SET latest_event_id=NULL
   WHERE narrative_id IN (SELECT narrative_id FROM private.narrative_publication_event
     WHERE id IN (SELECT (pk->>'id')::uuid FROM private.person_purge_manifest WHERE tabel='private.narrative_publication_event'));
  -- Børn slettes først; rollback til sidst genskaber alt. Mere end én række pr. tabel udøver begge S49b-veje og Q6.
  FOR r IN SELECT m.tabel,m.pk FROM private.person_purge_manifest m
    WHERE m.tabel IN (SELECT tabel FROM private.person_purge_tilladte_tabeller())
    ORDER BY CASE m.tabel WHEN 'private.text_revision_reconciliation' THEN 1 WHEN 'private.relation_reopen' THEN 2
      WHEN 'private.interpretation_promotion' THEN 3 WHEN 'private.identity_control_parent_event' THEN 4
      WHEN 'private.identity_control_parent_card' THEN 5 WHEN 'private.reimport_name_completion_result' THEN 6
      WHEN 'private.reimport_event' THEN 7 ELSE 8 END,m.pk LOOP
    EXECUTE pg_temp.slet_sql(r.tabel,r.pk);
    GET DIAGNOSTICS v_n=ROW_COUNT;
    IF v_n<>1 THEN RAISE EXCEPTION 'TEST_FAILED manifest_grunde: %',r.tabel; END IF;
  END LOOP;
END $t$;
ROLLBACK;
\echo OK update_uaendret_forbudt
\echo OK manifest_alle_tilladte_tabeller

-- TRUNCATE må ikke kalde rækkehjælperen eller tilgå OLD. Test alle eksisterende statement-vagter enkeltvis
-- med CASCADE, så en FK-afvisning ikke kan give et falsk grønt resultat.
BEGIN;
DO $t$ BEGIN PERFORM pg_temp.manifest(); END $t$;
DO $t$
DECLARE r record; v_count int:=0;
BEGIN
  FOR r IN SELECT n.nspname||'.'||c.relname AS tabel
    FROM pg_trigger t JOIN pg_class c ON c.oid=t.tgrelid JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname='private' AND NOT t.tgisinternal AND (t.tgtype::int & 32)=32
      AND c.relname IN ('source_persona_identity_event','source_persona_identity_candidate','interpretation_promotion',
        'legacy_placement_disposition','identity_control_parent_card','identity_control_parent_event',
        'relation_reopen','text_revision_reconciliation') ORDER BY c.relname LOOP
    v_count:=v_count+1;
    -- CASCADE kan møde en anden evidenstabel først; kræv den uændrede evidens-fejlfamilie, aldrig permission/OLD-fejl.
    DECLARE v_error text;
    BEGIN
      BEGIN EXECUTE format('TRUNCATE %s CASCADE',r.tabel); EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM; END;
      IF v_error IS NULL OR v_error NOT LIKE 'EVIDENCE_APPEND_ONLY: private.% kan ikke TRUNCATE' THEN
        RAISE EXCEPTION 'TEST_FAILED truncate_uaendret: %, %',r.tabel,v_error;
      END IF;
    END;
  END LOOP;
  -- Målt 16/11 på skabelonen før Task 5: interpretation_promotion og source_persona_identity_event har ingen
  -- TRUNCATE-vagt (kun rækkevagter); de 6 andre har. Task 5 ændrer ingen TRUNCATE-triggere (global-constraints).
  IF v_count<>6 THEN RAISE EXCEPTION 'TEST_FAILED truncate_uaendret: forventet 6 vagter, fik %',v_count; END IF;
END $t$;
ROLLBACK;
\echo OK truncate_uaendret

BEGIN;
DO $q5$
DECLARE v_rel bigint; v_assertion bigint; v_i uuid; v_template private.interpretation%ROWTYPE;
  v_other uuid:=purge_test.u('T1'); v_prom uuid[]:='{}'; v_id uuid; r record;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','a2a00000-0000-4000-8000-00000000a001',true);
  PERFORM purge_test.nyt();
  IF NOT EXISTS (SELECT 1 FROM private.source_persona_identity
    WHERE source_persona_id=v_other AND canonical_person_id=purge_test.id('tredje') AND decision_status='accepted') THEN
    RAISE EXCEPTION 'TEST_FAILED plan_q5_overlap: andens persona mangler';
  END IF;
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('person',purge_test.id('P'),'fact',purge_test.id('fakta_vielse_del'),'omtaler') RETURNING id INTO v_rel;
  INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst)
    VALUES ('relation',v_rel,'Syntetisk familieudsagn') RETURNING id INTO v_assertion;
  SELECT i.* INTO STRICT v_template FROM private.interpretation i JOIN private.interpretation_promotion p
    ON p.interpretation_id=i.id WHERE p.id=purge_test.u('prom_egen');
  INSERT INTO private.interpretation(interpretation_key,version,source_id,source_persona_id,interpretation_kind,
    predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
    VALUES (gen_random_uuid(),1,v_template.source_id,v_other,v_template.interpretation_kind,
      v_template.predicate,v_template.value,v_template.schema_version,v_template.derivation_kind,1,'proposed','fixture',v_template.extraction_run_id)
    RETURNING id INTO v_i;
  INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
    SELECT v_i,observation_id,evidence_role,ordinal FROM private.interpretation_observation WHERE interpretation_id=v_template.id;
  v_i:=public.red_decide_interpretation(v_i,1,'accepted','{"basis":"purge-q5-overlap"}');
  FOR r IN SELECT * FROM (VALUES ('relation',v_rel),('assertion',v_assertion)) t(typ,id) LOOP
    INSERT INTO private.interpretation_promotion(interpretation_id,target_type,target_id,evidence,promoted_by,promoted_by_name)
      VALUES (v_i,r.typ,r.id,'{"fixture":"q5-overlap"}','a2a00000-0000-4000-8000-00000000a001','Purge-redaktør')
      RETURNING id INTO v_id;
    v_prom:=array_append(v_prom,v_id);
  END LOOP;
  FOR v_id IN SELECT unnest(v_prom) LOOP
    INSERT INTO private.person_purge_manifest VALUES
      (pg_current_xact_id(),pg_backend_pid(),purge_test.id('P'),'private.interpretation_promotion',
       jsonb_build_object('id',v_id),'egen',NULL);
    PERFORM pg_temp.afvis(pg_temp.slet_sql('private.interpretation_promotion',jsonb_build_object('id',v_id)),
                         pg_temp.append_fejl('private.interpretation_promotion'));
  END LOOP;
  -- Den samme andens principal-persona må gerne have en promotion til P selv (Q5).
  INSERT INTO private.interpretation_promotion(interpretation_id,target_type,target_id,evidence,promoted_by,promoted_by_name)
    VALUES (v_i,'person',purge_test.id('P'),'{"fixture":"q5-person"}',
      'a2a00000-0000-4000-8000-00000000a001','Purge-redaktør') RETURNING id INTO v_id;
  INSERT INTO private.person_purge_manifest VALUES
    (pg_current_xact_id(),pg_backend_pid(),purge_test.id('P'),'private.interpretation_promotion',
     jsonb_build_object('id',v_id),'egen',NULL);
  EXECUTE pg_temp.slet_sql('private.interpretation_promotion',jsonb_build_object('id',v_id));
  IF EXISTS (SELECT 1 FROM private.interpretation_promotion WHERE id=v_id) THEN
    RAISE EXCEPTION 'TEST_FAILED manifest_q5: egen person med andens principal';
  END IF;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
END $q5$;
ROLLBACK;
\echo OK manifest_q5_overlap_og_andens_principal

-- Afledte rækker kræver en reference i samme persons manifest; målposten alene er ikke nok.
BEGIN;
DO $t$ BEGIN PERFORM pg_temp.manifest(); END $t$;
DELETE FROM private.person_purge_manifest
 WHERE tabel NOT IN ('private.relation_reopen','private.text_revision_reconciliation','private.identity_control_parent_event');
DO $t$
DECLARE r record; v_n int:=0;
BEGIN
  FOR r IN SELECT tabel,pk FROM private.person_purge_manifest LOOP
    v_n:=v_n+1;
    PERFORM pg_temp.afvis(pg_temp.slet_sql(r.tabel,r.pk),pg_temp.append_fejl(r.tabel));
  END LOOP;
  IF v_n<4 THEN RAISE EXCEPTION 'TEST_FAILED manifest_afledt_reference: manglende fixturrækker'; END IF;
END $t$;
DELETE FROM private.person_purge_manifest;
DO $t$ BEGIN PERFORM pg_temp.manifest(); END $t$;
UPDATE private.person_purge_manifest SET person_id=purge_test.id('tredje')
 WHERE tabel NOT IN ('private.relation_reopen','private.text_revision_reconciliation','private.identity_control_parent_event');
DO $t$
DECLARE r record; v_n int:=0;
BEGIN
  FOR r IN SELECT tabel,pk FROM private.person_purge_manifest
    WHERE tabel IN ('private.relation_reopen','private.text_revision_reconciliation','private.identity_control_parent_event') LOOP
    v_n:=v_n+1;
    PERFORM pg_temp.afvis(pg_temp.slet_sql(r.tabel,r.pk),pg_temp.append_fejl(r.tabel));
  END LOOP;
  IF v_n<4 THEN RAISE EXCEPTION 'TEST_FAILED manifest_afledt_reference: manglende fixturrækker'; END IF;
END $t$;
ROLLBACK;
\echo OK manifest_afledt_reference

-- Familiegrunden har sit eget uafhængige bevis. Omdan kun legacy-testnarrativets subjekt i denne rollback.
BEGIN;
DO $t$
DECLARE v_pk jsonb:=jsonb_build_object('id',purge_test.u('npe_legacy'));
  v_t text:='private.narrative_publication_event'; v_n bigint; v_fam bigint;
BEGIN
  IF EXISTS (SELECT 1 FROM public.family_member
      WHERE family_id=purge_test.id('fam_andre') AND person_id=purge_test.id('P'))
     OR NOT EXISTS (SELECT 1 FROM public.family_member
      WHERE family_id=purge_test.id('fam_keep') AND person_id=purge_test.id('P'))
     OR NOT EXISTS (SELECT 1 FROM public.family_member
      WHERE family_id=purge_test.id('fam_keep') AND person_id<>purge_test.id('P') AND rolle<>'partner') THEN
    RAISE EXCEPTION 'TEST_FAILED manifest_familienarrativ: manglende uvedkommende/bevaret familie';
  END IF;
  SELECT narrative_id INTO STRICT v_n FROM private.narrative_publication_event WHERE id=purge_test.u('npe_legacy');
  UPDATE public.narrative SET subjekt_type='family',subjekt_id=purge_test.id('fam_del') WHERE id=v_n;
  INSERT INTO private.person_purge_manifest VALUES
    (pg_current_xact_id(),pg_backend_pid(),purge_test.id('P'),v_t,v_pk,'egen',NULL);
  PERFORM pg_temp.afvis(pg_temp.slet_sql(v_t,v_pk),pg_temp.append_fejl(v_t));
  UPDATE private.person_purge_manifest SET grund='familie';
  PERFORM pg_temp.afvis(pg_temp.slet_sql(v_t,v_pk),pg_temp.append_fejl(v_t));
  INSERT INTO private.person_purge_manifest VALUES
    (pg_current_xact_id(),pg_backend_pid(),purge_test.id('tredje'),'family',
     jsonb_build_object('id',purge_test.id('fam_del')),'familie',NULL);
  PERFORM pg_temp.afvis(pg_temp.slet_sql(v_t,v_pk),pg_temp.append_fejl(v_t));
  UPDATE private.person_purge_manifest SET person_id=purge_test.id('P') WHERE tabel='family';
  UPDATE private.narrative_legacy_publication SET latest_event_id=NULL WHERE narrative_id=v_n;
  -- Selv en family-post med korrekt person/grund/PK må ikke autorisere Fam_keep eller en familie uden P.
  FOREACH v_fam IN ARRAY ARRAY[purge_test.id('fam_andre'),purge_test.id('fam_keep')] LOOP
    UPDATE public.narrative SET subjekt_id=v_fam WHERE id=v_n;
    UPDATE private.person_purge_manifest SET pk=jsonb_build_object('id',v_fam) WHERE tabel='family';
    PERFORM pg_temp.afvis(pg_temp.slet_sql(v_t,v_pk),pg_temp.append_fejl(v_t));
  END LOOP;
  -- Samme event og manifest må fortsat slettes, når begge familiebeviser gælder for Fam_del.
  UPDATE public.narrative SET subjekt_id=purge_test.id('fam_del') WHERE id=v_n;
  UPDATE private.person_purge_manifest SET pk=jsonb_build_object('id',purge_test.id('fam_del')) WHERE tabel='family';
  EXECUTE pg_temp.slet_sql(v_t,v_pk);
  IF EXISTS (SELECT 1 FROM private.narrative_publication_event WHERE id=purge_test.u('npe_legacy')) THEN
    RAISE EXCEPTION 'TEST_FAILED manifest_familienarrativ';
  END IF;
END $t$;
ROLLBACK;
\echo OK manifest_familienarrativ
\echo OK manifest_familienarrativ_uvedkommende_og_bevaret_afvises

-- Triggere er automatisk kaldbare ved tabel-DML, også uden private USAGE/helper-EXECUTE.
-- Udøv alle fire vagter under de faktiske klientroller på en offentlig probe, med samme OLD-id som et manifest.
BEGIN;
CREATE TABLE public.purge_trigger_probe(id uuid PRIMARY KEY,canonical_person_id bigint);
INSERT INTO public.purge_trigger_probe VALUES(gen_random_uuid(),purge_test.id('P'));
GRANT SELECT,UPDATE,DELETE ON public.purge_trigger_probe TO anon,authenticated,service_role;
INSERT INTO private.person_purge_manifest(xid,backend_pid,person_id,tabel,pk,grund)
 SELECT pg_current_xact_id(),pg_backend_pid(),canonical_person_id,'private.purge_trigger_probe',jsonb_build_object('id',id),'egen'
 FROM public.purge_trigger_probe;
DO $t$
DECLARE v_func text; v_role text; v_error text; v_expected text;
BEGIN
  FOREACH v_func IN ARRAY ARRAY['reject_evidence_mutation','reject_reimport_writer_mutation',
    'reject_reimport_case_event_mutation','reject_narrative_publication_event_mutation'] LOOP
    EXECUTE format('CREATE TRIGGER probe BEFORE DELETE OR UPDATE ON public.purge_trigger_probe FOR EACH ROW EXECUTE FUNCTION private.%I()',v_func);
    v_expected:=CASE v_func WHEN 'reject_evidence_mutation' THEN 'EVIDENCE_APPEND_ONLY: public.purge_trigger_probe kan ikke DELETE'
      WHEN 'reject_reimport_writer_mutation' THEN 'REIMPORT_WRITER_APPEND_ONLY'
      WHEN 'reject_reimport_case_event_mutation' THEN 'REIMPORT_CASE_EVENT_APPEND_ONLY'
      ELSE 'NARRATIVE_PUBLICATION_EVENT_APPEND_ONLY' END;
    FOREACH v_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
      v_error:=NULL;
      EXECUTE format('SET LOCAL ROLE %I',v_role);
      BEGIN DELETE FROM public.purge_trigger_probe; EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM; END;
      RESET ROLE;
      IF v_error IS DISTINCT FROM v_expected THEN
        RAISE EXCEPTION 'TEST_FAILED manifest_rollefejl: %, %, %',v_func,v_role,v_error;
      END IF;
    END LOOP;
    DROP TRIGGER probe ON public.purge_trigger_probe;
  END LOOP;
END $t$;
ROLLBACK;
\echo OK afvisningstekst_klientroller

DO $t$
DECLARE v_role text; v_t text;
BEGIN
  FOREACH v_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    IF has_schema_privilege(v_role,'private','USAGE') THEN
      RAISE EXCEPTION 'TEST_FAILED manifest_klientrettigheder: private USAGE';
    END IF;
    IF has_table_privilege(v_role,'private.person_purge_manifest','SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
       OR has_function_privilege(v_role,'private.person_purge_tilladt(text,jsonb)','EXECUTE')
       OR has_function_privilege(v_role,'private.person_purge_tilladte_tabeller()','EXECUTE')
       OR has_function_privilege(v_role,'private.person_purge_fam_del(bigint)','EXECUTE') THEN
      RAISE EXCEPTION 'TEST_FAILED manifest_klientrettigheder: manifest/helper';
    END IF;
    FOR v_t IN SELECT tabel FROM private.person_purge_tilladte_tabeller() LOOP
      IF has_table_privilege(v_role,v_t,'DELETE') THEN RAISE EXCEPTION 'TEST_FAILED manifest_klientrettigheder: DELETE'; END IF;
    END LOOP;
  END LOOP;
  IF NOT (SELECT relrowsecurity FROM pg_class WHERE oid='private.person_purge_manifest'::regclass) THEN
    RAISE EXCEPTION 'TEST_FAILED manifest_rls';
  END IF;
  FOR v_t IN SELECT tabel FROM private.person_purge_tilladte_tabeller() LOOP
    IF NOT EXISTS (SELECT 1 FROM pg_trigger t WHERE t.tgrelid=to_regclass(v_t) AND NOT t.tgisinternal
      AND t.tgenabled='O' AND (t.tgtype::int & 25)=25
      AND t.tgfoid IN ('private.reject_evidence_mutation()'::regprocedure,'private.reject_reimport_writer_mutation()'::regprocedure,
        'private.reject_reimport_case_event_mutation()'::regprocedure,'private.reject_narrative_publication_event_mutation()'::regprocedure)) THEN
      RAISE EXCEPTION 'TEST_FAILED trigger_enabled: manglende rækkevagt på %',v_t;
    END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM pg_trigger t WHERE NOT t.tgisinternal
    AND t.tgfoid IN ('private.reject_evidence_mutation()'::regprocedure,'private.reject_reimport_writer_mutation()'::regprocedure,
      'private.reject_reimport_case_event_mutation()'::regprocedure,'private.reject_narrative_publication_event_mutation()'::regprocedure)
    AND t.tgenabled<>'O') THEN RAISE EXCEPTION 'TEST_FAILED trigger_enabled'; END IF;
END $t$;
\echo OK trigger_enabled
\echo OK manifest_klientrettigheder
-- Et vellykket DELETE skal overleve COMMIT og må kun ramme netop den manifesterede kandidat.
BEGIN;
CREATE TEMP TABLE valgt_kandidat AS SELECT id FROM private.source_persona_identity_candidate
 WHERE candidate_person_id=purge_test.id('P') ORDER BY id LIMIT 1;
CREATE TEMP TABLE andre_kandidater AS SELECT * FROM private.source_persona_identity_candidate
 WHERE id<>(SELECT id FROM valgt_kandidat);
INSERT INTO private.person_purge_manifest(xid,backend_pid,person_id,tabel,pk,grund)
 SELECT pg_current_xact_id(),pg_backend_pid(),purge_test.id('P'),'private.source_persona_identity_candidate',
        jsonb_build_object('id',id),'egen' FROM valgt_kandidat;
DELETE FROM private.source_persona_identity_candidate WHERE id=(SELECT id FROM valgt_kandidat);
COMMIT;
DO $t$
BEGIN
  IF (SELECT count(*) FROM valgt_kandidat)<>1
     OR EXISTS (SELECT 1 FROM private.source_persona_identity_candidate WHERE id=(SELECT id FROM valgt_kandidat))
     OR EXISTS ((SELECT * FROM andre_kandidater EXCEPT SELECT * FROM private.source_persona_identity_candidate)
                UNION ALL (SELECT * FROM private.source_persona_identity_candidate EXCEPT SELECT * FROM andre_kandidater)) THEN
    RAISE EXCEPTION 'TEST_FAILED manifest_tillader_egen_raekke';
  END IF;
END $t$;
\echo OK manifest_tillader_egen_raekke
\endif
