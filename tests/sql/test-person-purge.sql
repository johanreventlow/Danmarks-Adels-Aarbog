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
SELECT :'gruppe' IN ('inventar','binding','plan','historik','fortrydelse','manifest','oprindelse','preview','preview_q3','vagt','purge','purge_ekstra','purge_binding','fortryd_link','db_verify','udbakke','purge_gdpr') AS gruppe_kendt,
       :'gruppe'='udbakke' AS g_udbakke, :'gruppe'='inventar' AS g_inventar, :'gruppe'='binding' AS g_binding,
       :'gruppe'='plan' AS g_plan, :'gruppe'='historik' AS g_historik, :'gruppe'='fortrydelse' AS g_fortrydelse,
       :'gruppe'='manifest' AS g_manifest, :'gruppe'='oprindelse' AS g_oprindelse,
       :'gruppe'='preview' AS g_preview, :'gruppe'='preview_q3' AS g_preview_q3,
       :'gruppe'='vagt' AS g_vagt, :'gruppe'='fortryd_link' AS g_fortryd_link, :'gruppe'='db_verify' AS g_db_verify,
       :'gruppe'='purge_binding' AS g_purge_binding, :'gruppe'='purge' AS g_purge, :'gruppe'='purge_ekstra' AS g_purge_ekstra,
       :'gruppe'='purge_gdpr' AS g_purge_gdpr,
       :'gruppe' IN ('preview','preview_q3') AS g_preview_helpers \gset
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
    'S35','S36','S37','S37b','NY-E','S38','S38b',
    -- §1e (+ Q6)
    'S39a','S39b','S39c','S39f','Prom_egen_fam','S40','S41a','S41b','S42','S43a','S43b','S44a','S44b','S45a','M5','S45b',
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
      OR handling IS NULL OR handling NOT IN ('slet','nulstil','loesn','skjul','bevar_andres','blokér','ingen')
      -- skjul (NY-E, review 37 P1+P2) er en planlagt UPDATE uden manifest: fase, men ingen grund.
      OR (handling='skjul' AND (grund IS NOT NULL OR fase IS NULL))
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
 ('{S35}','{S35}'),('{S36}','{S36}'),('{S37}','{S37c}'),('{NY-E}','{NY-E}'),('{S38}','{S38}'),
 ('{S39a,Prom_egen_fam}','{S39}'),('{S39f}','{S39f}'),('{S40}','{S40}'),('{S41a}','{S41}'),('{S42}','{S42}'),
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

-- P's eksklusive medie skal slettes, selv om P's EGEN narrativ og note linker til det (text_mention fra en tekst, der
-- selv slettes, holder ikke mediet i live). Modprøven (link fra en andens narrativ/note bevarer mediet) står i
-- preview_blokering_link.
BEGIN;
DO $mediemention$
DECLARE v_kilde text; v_token text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM private.person_purge_plan(purge_test.id('P'))
      WHERE tabel='media' AND handling='slet' AND pk=jsonb_build_object('id',purge_test.id('medie_eksklusiv'))) THEN
    RAISE EXCEPTION 'TEST_FAILED plan_egen_mention_medie baseline';
  END IF;
  v_token:=format(' [[media:%s|fixture]]',purge_test.id('medie_eksklusiv'));
  FOREACH v_kilde IN ARRAY ARRAY['narrative','note'] LOOP
    BEGIN
      PERFORM purge_test.nyt(); PERFORM public.begin_change_set('plan_egen_mention','fixture');
      IF v_kilde='narrative' THEN
        UPDATE public.narrative SET tekst=tekst||v_token WHERE id=purge_test.id('narrativ_P');
      ELSE
        UPDATE public.note SET indhold=indhold||v_token WHERE id=purge_test.id('note_P');
      END IF;
      IF NOT EXISTS (SELECT 1 FROM public.text_mention WHERE maal_type='media' AND maal_id=purge_test.id('medie_eksklusiv')
          AND kilde_type=v_kilde) THEN
        RAISE EXCEPTION 'TEST_FAILED plan_egen_mention_medie fixture %',v_kilde;
      END IF;
      IF NOT EXISTS (SELECT 1 FROM private.person_purge_plan(purge_test.id('P'))
          WHERE tabel='media' AND handling='slet' AND pk=jsonb_build_object('id',purge_test.id('medie_eksklusiv'))) THEN
        RAISE EXCEPTION 'TEST_FAILED plan_egen_mention_medie %',v_kilde;
      END IF;
      RAISE SQLSTATE 'ZX001';
    EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL; END;
  END LOOP;
END $mediemention$;
\echo OK plan_egen_mention_medie
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
SELECT 1 / CASE WHEN :reversal_advarsler=0 AND :reversal_noter=1 THEN 1 ELSE 0 END;
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
SELECT 1 / CASE WHEN :reversal_advarsler=2 AND :reversal_noter=1 THEN 1 ELSE 0 END;
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
  -- Selv en family-post med korrekt person/grund/PK må ikke autorisere Fam_keep eller en familie uden P. Fam_keep
  -- prøves med en OFFENTLIG P: er P ikke-offentlig, er Fam_keep Fam_ind (review 37 P1+P2, løsning A; nedenfor).
  UPDATE public.person SET privat=false WHERE id=purge_test.id('P');
  FOREACH v_fam IN ARRAY ARRAY[purge_test.id('fam_andre'),purge_test.id('fam_keep')] LOOP
    UPDATE public.narrative SET subjekt_id=v_fam WHERE id=v_n;
    UPDATE private.person_purge_manifest SET pk=jsonb_build_object('id',v_fam) WHERE tabel='family';
    PERFORM pg_temp.afvis(pg_temp.slet_sql(v_t,v_pk),pg_temp.append_fejl(v_t));
  END LOOP;
  -- Ikke-offentlig P (fixturens): Fam_keep, hvor P er partner, autoriseres af det uafhængige Fam_ind-bevis, også
  -- uden at manifestets family-post peger på den. En familie uden P afvises stadig.
  UPDATE public.person SET privat=true WHERE id=purge_test.id('P');
  UPDATE public.narrative SET subjekt_id=purge_test.id('fam_andre') WHERE id=v_n;
  PERFORM pg_temp.afvis(pg_temp.slet_sql(v_t,v_pk),pg_temp.append_fejl(v_t));
  UPDATE public.narrative SET subjekt_id=purge_test.id('fam_keep') WHERE id=v_n;
  UPDATE private.person_purge_manifest SET pk=jsonb_build_object('id',purge_test.id('fam_del')) WHERE tabel='family';
  BEGIN
    EXECUTE pg_temp.slet_sql(v_t,v_pk);
    IF EXISTS (SELECT 1 FROM private.narrative_publication_event WHERE id=purge_test.u('npe_legacy')) THEN
      RAISE EXCEPTION 'TEST_FAILED manifest_familienarrativ_fam_ind';
    END IF;
    RAISE SQLSTATE 'ZX002';
  EXCEPTION WHEN SQLSTATE 'ZX002' THEN NULL;
  END;
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
\echo OK manifest_familienarrativ_fam_ind

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

-- =====================================================================================================================
-- Gruppe oprindelse (Task 6 / Q7). Simulér kun identitetsdelen af Task 8: håndskrevet manifest, events før state.
-- Ingen planfunktion autoriserer testene. Negative kald kræver den præcise fejl; en anden constraint tæller ikke.
-- =====================================================================================================================
\if :g_oprindelse
SET request.jwt.claim.sub='a2a00000-0000-4000-8000-00000000a001';
CREATE FUNCTION pg_temp.oprindelse_afvis(p_sql text,p_error text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_error text;
BEGIN
  BEGIN EXECUTE p_sql; EXCEPTION WHEN OTHERS THEN v_error:=SQLERRM; END;
  IF v_error IS DISTINCT FROM p_error THEN
    RAISE EXCEPTION 'TEST_FAILED oprindelse: forventet %, fik %',p_error,v_error;
  END IF;
END $$;
CREATE FUNCTION pg_temp.purge_kald() RETURNS integer
LANGUAGE sql SECURITY DEFINER SET search_path=pg_catalog,public,private AS $$
  SELECT private.decide_source_persona_identity(purge_test.u('X2'),NULL,0,'rejected','{"reason":"not_a_person"}','person_purge')
$$;
CREATE FUNCTION pg_temp.toem_identitet() RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_x uuid:=purge_test.u('X2'); v_n int;
BEGIN
  SELECT max(version) INTO v_n FROM private.source_persona_identity_event WHERE source_persona_id=v_x;
  IF v_n IS NULL OR NOT EXISTS (SELECT 1 FROM private.source_persona_identity
      WHERE source_persona_id=v_x AND version=v_n AND decision_status='accepted' AND canonical_person_id=purge_test.id('P')) THEN
    RAISE EXCEPTION 'TEST_FAILED oprindelse: manglende accepteret teststrøm';
  END IF;
  INSERT INTO private.person_purge_manifest(xid,backend_pid,person_id,tabel,pk,grund,forrige_version)
    VALUES (pg_current_xact_id(),pg_backend_pid(),purge_test.id('P'),'private.source_persona_identity',
            jsonb_build_object('source_persona_id',v_x),'hel_stroem',v_n);
  INSERT INTO private.person_purge_manifest(xid,backend_pid,person_id,tabel,pk,grund)
    SELECT pg_current_xact_id(),pg_backend_pid(),purge_test.id('P'),'private.source_persona_identity_event',
           jsonb_build_object('id',id),'hel_stroem'
      FROM private.source_persona_identity_event WHERE source_persona_id=v_x;
  DELETE FROM private.source_persona_identity_event WHERE source_persona_id=v_x;
  DELETE FROM private.source_persona_identity WHERE source_persona_id=v_x;
END $$;
-- Direkte INSERT omgår kernen, så validatoren skal kunne stå alene. Auditfelter er ellers gyldige.
CREATE FUNCTION pg_temp.identitetsevent(p_version int,p_evidence jsonb DEFAULT '{"reason":"not_a_person"}',
  p_status text DEFAULT 'rejected',p_person bigint DEFAULT NULL) RETURNS void LANGUAGE sql AS $$
  INSERT INTO private.source_persona_identity_event(source_persona_id,version,evidence,decision_status,canonical_person_id,
    decided_by,decided_by_name,decided_at)
  VALUES (purge_test.u('X2'),p_version,p_evidence,p_status,p_person,auth.uid(),'Purge-redaktør',clock_timestamp())
$$;

BEGIN;
DO $t$
DECLARE r record;
BEGIN
  PERFORM pg_temp.toem_identitet();
  FOR r IN SELECT * FROM (VALUES
    ('accepted',NULL::bigint,0,'{"reason":"not_a_person"}'::jsonb),
    ('unresolved',NULL,0,'{"reason":"not_a_person"}'),
    ('superseded',NULL,0,'{"reason":"not_a_person"}'),
    ('proposed',NULL,0,'{"reason":"not_a_person"}'),
    (NULL,NULL,0,'{"reason":"not_a_person"}'),
    ('rejected',purge_test.id('P'),0,'{"reason":"not_a_person"}'),
    ('rejected',NULL,1,'{"reason":"not_a_person"}'),
    ('rejected',NULL,-1,'{"reason":"not_a_person"}'),
    ('rejected',NULL,NULL,'{"reason":"not_a_person"}'),
    ('rejected',NULL,0,NULL),
    ('rejected',NULL,0,'null'),
    ('rejected',NULL,0,'{}'),
    ('rejected',NULL,0,'[]'),
    ('rejected',NULL,0,'{"reason":"new_person_needed"}'),
    ('rejected',NULL,0,'{"reason":"not_a_person","basis":"web_detail"}'),
    ('rejected',NULL,0,'{"reason":"not_a_person","extra":true}')
  ) AS bad(status,person_id,expected_version,evidence) LOOP
    PERFORM pg_temp.oprindelse_afvis(format(
      'SELECT private.decide_source_persona_identity(purge_test.u(''X2''),%L::bigint,%L::int,%L,%L::jsonb,''person_purge'')',
      r.person_id,r.expected_version,r.status,r.evidence),'EVIDENCE_PERSON_PURGE_SHAPE');
  END LOOP;
END $t$;
ROLLBACK;
\echo OK purge_oprindelse_form

-- En rigtig kvittering giver hverken lov til at springe over eksisterende events eller at genbruge state.
BEGIN;
INSERT INTO private.person_purge_manifest VALUES
  (pg_current_xact_id(),pg_backend_pid(),purge_test.id('P'),'private.source_persona_identity',
   jsonb_build_object('source_persona_id',purge_test.u('X2')),'hel_stroem',3);
DO $t$ BEGIN
  PERFORM pg_temp.oprindelse_afvis('SELECT pg_temp.purge_kald()','EVIDENCE_PERSON_PURGE_SHAPE');
  DELETE FROM private.source_persona_identity WHERE source_persona_id=purge_test.u('X2');
  PERFORM pg_temp.oprindelse_afvis('SELECT pg_temp.purge_kald()','EVIDENCE_PERSON_PURGE_SHAPE');
  -- Manifestets n+1=5 ville passe, men max+1 er 4, og strømmen er ikke tom.
  UPDATE private.person_purge_manifest SET forrige_version=4;
  PERFORM pg_temp.oprindelse_afvis('SELECT pg_temp.identitetsevent(5)',
    'EVIDENCE_IDENTITY_VERSION_CONFLICT: expected 4, got 5');
END $t$;
ROLLBACK;
\echo OK purge_kraever_slettet_stroem

BEGIN;
DO $t$
DECLARE v_manifest jsonb; v_bad jsonb;
BEGIN
  PERFORM pg_temp.toem_identitet();
  SELECT to_jsonb(m) INTO v_manifest FROM private.person_purge_manifest m WHERE tabel='private.source_persona_identity';
  DELETE FROM private.person_purge_manifest WHERE tabel='private.source_persona_identity';
  -- Direkte og gennem en SECURITY DEFINER-serverfunktion, selv med eventposter i manifestet.
  PERFORM pg_temp.oprindelse_afvis(
    'SELECT private.decide_source_persona_identity(purge_test.u(''X2''),NULL,0,''rejected'',''{"reason":"not_a_person"}'',''person_purge'')',
    'EVIDENCE_PERSON_PURGE_SHAPE');
  PERFORM pg_temp.oprindelse_afvis('SELECT pg_temp.purge_kald()','EVIDENCE_PERSON_PURGE_SHAPE');
  PERFORM pg_temp.oprindelse_afvis('SELECT pg_temp.identitetsevent(4)',
    'EVIDENCE_IDENTITY_VERSION_CONFLICT: expected 1, got 4');
  -- Hver probe prøves mod BÅDE kernen og validatoren. PK er lighed, aldrig containment.
  FOR v_bad IN SELECT value FROM jsonb_array_elements(jsonb_build_array(
    jsonb_build_object('xid','1'),
    jsonb_build_object('backend_pid',pg_backend_pid()+1),
    jsonb_build_object('tabel','source_persona_identity'),
    jsonb_build_object('grund','egen'),
    jsonb_build_object('pk','{}'::jsonb),
    jsonb_build_object('pk',jsonb_build_object('source_persona_id',purge_test.u('X2'),'extra',true)),
    jsonb_build_object('pk',jsonb_build_object('source_persona_id',purge_test.u('X1'))),
    jsonb_build_object('forrige_version',NULL),
    jsonb_build_object('forrige_version',0),
    jsonb_build_object('forrige_version',-1)
  )) LOOP
    INSERT INTO private.person_purge_manifest SELECT (jsonb_populate_record(NULL::private.person_purge_manifest,v_manifest||v_bad)).*;
    PERFORM pg_temp.oprindelse_afvis('SELECT pg_temp.purge_kald()','EVIDENCE_PERSON_PURGE_SHAPE');
    PERFORM pg_temp.oprindelse_afvis('SELECT pg_temp.identitetsevent(4)',
      'EVIDENCE_IDENTITY_VERSION_CONFLICT: expected 1, got 4');
    DELETE FROM private.person_purge_manifest WHERE tabel<>'private.source_persona_identity_event';
  END LOOP;
END $t$;
ROLLBACK;
\echo OK purge_oprindelse_kraever_manifest
\echo OK purge_validator_kraever_praecist_manifest

BEGIN;
DO $t$
DECLARE v_ev jsonb; v_status text;
BEGIN
  PERFORM pg_temp.toem_identitet();
  PERFORM pg_temp.oprindelse_afvis('SELECT pg_temp.identitetsevent(5)',
    'EVIDENCE_IDENTITY_VERSION_CONFLICT: expected 1, got 5');
  FOR v_ev IN SELECT value FROM jsonb_array_elements('[{}, {"reason":"new_person_needed"},
      {"reason":"not_a_person","extra":true}, null]'::jsonb) LOOP
    PERFORM pg_temp.oprindelse_afvis(format('SELECT pg_temp.identitetsevent(4,%L::jsonb)',v_ev),
      'EVIDENCE_IDENTITY_VERSION_CONFLICT: expected 1, got 4');
  END LOOP;
  PERFORM pg_temp.oprindelse_afvis('SELECT pg_temp.identitetsevent(4,NULL)',
    'EVIDENCE_IDENTITY_VERSION_CONFLICT: expected 1, got 4');
  FOREACH v_status IN ARRAY ARRAY['accepted','unresolved','superseded','proposed'] LOOP
    PERFORM pg_temp.oprindelse_afvis(format('SELECT pg_temp.identitetsevent(4,''{"reason":"not_a_person"}'',%L)',v_status),
      'EVIDENCE_IDENTITY_VERSION_CONFLICT: expected 1, got 4');
  END LOOP;
  PERFORM pg_temp.oprindelse_afvis('SELECT pg_temp.identitetsevent(4,''{"reason":"not_a_person"}'',''rejected'',purge_test.id(''P''))',
    'EVIDENCE_IDENTITY_VERSION_CONFLICT: expected 1, got 4');
END $t$;
ROLLBACK;
\echo OK purge_validator_kun_n_plus_1_og_purgeform

-- Den positive test COMMIT'er: også de deferred state/event-triggere skal bestå.
BEGIN;
CREATE TEMP TABLE gamle_identitetsevents AS SELECT id,version FROM private.source_persona_identity_event
 WHERE source_persona_id=purge_test.u('X2');
CREATE TEMP TABLE andre_identitetsevents AS SELECT * FROM private.source_persona_identity_event
 WHERE source_persona_id<>purge_test.u('X2');
CREATE TEMP TABLE andre_identiteter AS SELECT * FROM private.source_persona_identity
 WHERE source_persona_id<>purge_test.u('X2');
DO $t$ BEGIN
  IF (SELECT array_agg(version ORDER BY version) FROM gamle_identitetsevents) IS DISTINCT FROM ARRAY[1,2,3] THEN
    RAISE EXCEPTION 'TEST_FAILED purge_version_n_plus_1: kræver v1..v3';
  END IF;
  PERFORM pg_temp.toem_identitet();
  IF pg_temp.purge_kald() IS DISTINCT FROM 4 THEN RAISE EXCEPTION 'TEST_FAILED purge_version_n_plus_1: returversion'; END IF;
  -- Kvitteringen giver ikke lov til at gentage kaldet, når v4 findes.
  PERFORM pg_temp.oprindelse_afvis('SELECT pg_temp.purge_kald()','EVIDENCE_PERSON_PURGE_SHAPE');
END $t$;
DELETE FROM private.person_purge_manifest;
COMMIT;
DO $t$
DECLARE v_event private.source_persona_identity_event%ROWTYPE;
BEGIN
  SELECT * INTO STRICT v_event FROM private.source_persona_identity_event WHERE source_persona_id=purge_test.u('X2');
  IF v_event.version<>4 OR v_event.decision_status<>'rejected' OR v_event.canonical_person_id IS NOT NULL
     OR v_event.evidence<>'{"reason":"not_a_person"}'::jsonb
     OR v_event.id<>private.content_uuid('identity-event',jsonb_build_object('source_persona_id',purge_test.u('X2'),'version',4))
     OR v_event.id IN (SELECT id FROM gamle_identitetsevents)
     OR NOT EXISTS (SELECT 1 FROM private.source_persona_identity i
       WHERE i.source_persona_id=v_event.source_persona_id AND i.version=4 AND i.decision_status='rejected'
         AND i.canonical_person_id IS NULL AND i.evidence=v_event.evidence)
     OR EXISTS ((SELECT * FROM andre_identitetsevents EXCEPT SELECT * FROM private.source_persona_identity_event WHERE source_persona_id<>purge_test.u('X2'))
       UNION ALL (SELECT * FROM private.source_persona_identity_event WHERE source_persona_id<>purge_test.u('X2') EXCEPT SELECT * FROM andre_identitetsevents))
     OR EXISTS ((SELECT * FROM andre_identiteter EXCEPT SELECT * FROM private.source_persona_identity WHERE source_persona_id<>purge_test.u('X2'))
       UNION ALL (SELECT * FROM private.source_persona_identity WHERE source_persona_id<>purge_test.u('X2') EXCEPT SELECT * FROM andre_identiteter)) THEN
    RAISE EXCEPTION 'TEST_FAILED purge_version_n_plus_1';
  END IF;
END $t$;
\echo OK purge_version_n_plus_1

BEGIN;
DO $t$
DECLARE v_origin text; v_ev jsonb;
BEGIN
  FOREACH v_origin IN ARRAY ARRAY['person_create','legacy_match','relation_person_create'] LOOP
    v_ev:=CASE v_origin WHEN 'legacy_match' THEN jsonb_build_object('authority','person_external_id',
      'person_external_id',jsonb_build_object('person_id',purge_test.id('P'),'source_id',purge_test.id('kilde_a'),'record_key','PURGE-P'))
      WHEN 'relation_person_create' THEN '{"batch_id":"purge-test","method":"relation-person-create-v1","deceased":{}}'::jsonb
      ELSE '{"batch_id":"purge-test"}'::jsonb END;
    PERFORM pg_temp.oprindelse_afvis(format(
      'SELECT private.decide_source_persona_identity(purge_test.u(''X2''),purge_test.id(''P''),0,''accepted'',%L::jsonb,%L)',v_ev,v_origin),
      'EVIDENCE_IDENTITY_VERSION_CONFLICT: expected 0, current 4');
    -- relation_person_create har ikke et eget expected_version=0-krav. Den skal også afvise den aktuelle version.
    IF v_origin='relation_person_create' THEN
      PERFORM pg_temp.oprindelse_afvis(format(
        'SELECT private.decide_source_persona_identity(purge_test.u(''X2''),purge_test.id(''P''),4,''accepted'',%L::jsonb,%L)',v_ev,v_origin),
        'RELATION_PERSON_CREATE_ORIGIN_INVALID');
    END IF;
  END LOOP;
  -- En almindelig menneskelig afgørelse fortsætter stadig på max+1; purge-kvitteringen er nu væk.
  IF private.decide_source_persona_identity(purge_test.u('X2'),NULL,4,'unresolved',
      '{"basis":"web_detail","reason":"review"}','human') IS DISTINCT FROM 5 THEN
    RAISE EXCEPTION 'TEST_FAILED purge: almindelig oprindelse ændret';
  END IF;
END $t$;
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
\echo OK purge_spaerrer_genoprettelse
\echo OK purge_bevarer_almindelig_versionsregel

-- Minimal kontrolfixture: en ny gældende kandidatkørsel og et håndskrevet stikprøvekort på den aktuelle persona.
-- Status beregnes rigtigt både før og efter. Ingen eksisterende kontrolkørsel eller append-only-række omskrives.
BEGIN;
DO $t$
DECLARE v_run uuid; v_ctl uuid; v_candidate uuid:=gen_random_uuid(); v_version int; v_status text;
  v_actor uuid:=auth.uid(); v_sheet text:=repeat('6',64); v_rows text:=repeat('7',64);
BEGIN
  -- Gør personaen accepted igen i denne rollback-kopi, så den simulerede sletning har sin normale forudsætning.
  v_version:=private.decide_source_persona_identity(purge_test.u('X2'),purge_test.id('P'),4,'accepted',
    '{"basis":"web_detail"}','human');
  INSERT INTO private.source_persona_identity_candidate_run(source_id,generator_version,config,config_sha256,input_spec,
    input_sha256,candidates_sha256,persona_count,candidate_count,created_by,created_by_name)
  VALUES (purge_test.id('kilde_a'),'purge-control-test','{}',repeat('6',64),'{}',repeat('7',64),repeat('8',64),1,0,v_actor,'Purge-redaktør')
  RETURNING id INTO v_run;
  INSERT INTO private.identity_control_run(source_id,candidate_run_id,identity_population_sha256,relation_population_sha256,
    input_list_sha256,created_by)
  VALUES (purge_test.id('kilde_a'),v_run,repeat('8',64),repeat('9',64),private.control_input_list_sha256(v_run),v_actor)
  RETURNING id INTO v_ctl;
  INSERT INTO private.identity_control_sample(control_run_id,sample_kind,stratum,source_persona_id,identity_version,mapping,expected)
  VALUES (v_ctl,'identity','single_family',purge_test.u('X2'),v_version,jsonb_build_object('1',v_candidate::text),v_candidate::text);
  PERFORM private.append_control_event(v_ctl,'sealed',NULL,v_sheet,v_rows);
  v_version:=private.decide_source_persona_identity(purge_test.u('X2'),purge_test.id('P'),v_version,'accepted',
    jsonb_build_object('basis','human_sheet','sheet_sha256',v_sheet,'rows_sha256',v_rows,'control_run_id',v_ctl::text,
      'display_position',1,'candidate_id',v_candidate::text),'human');
  SELECT status INTO v_status FROM private.control_run_status(v_ctl);
  IF v_status IS DISTINCT FROM 'passed' THEN RAISE EXCEPTION 'TEST_FAILED purge_kontrolkoersel_failed: før'; END IF;
  PERFORM private.append_control_event(v_ctl,'passed','ok');
  PERFORM pg_temp.toem_identitet();
  IF pg_temp.purge_kald() IS DISTINCT FROM v_version+1 THEN RAISE EXCEPTION 'TEST_FAILED purge_kontrolkoersel_failed: version'; END IF;
  SELECT status INTO v_status FROM private.control_run_status(v_ctl);
  IF v_status IS DISTINCT FROM 'failed' THEN RAISE EXCEPTION 'TEST_FAILED purge_kontrolkoersel_failed: efter'; END IF;
END $t$;
SET CONSTRAINTS ALL IMMEDIATE;
ROLLBACK;
\echo OK purge_kontrolkoersel_failed
\endif

-- =====================================================================================================================
-- Task 7. Alle mutationer er syntetiske og rulles tilbage. Ingen tekst i fejl/output.
-- =====================================================================================================================
\if :g_preview_helpers
SET request.jwt.claim.sub='a2a00000-0000-4000-8000-00000000a001';
CREATE FUNCTION pg_temp.preview_assert(p_ok boolean,p_test text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'TEST_FAILED %',p_test; END IF; END $$;
CREATE FUNCTION pg_temp.preview_has(p_json jsonb,p_art text,p_tabel text DEFAULT NULL,p_pk jsonb DEFAULT NULL)
RETURNS boolean LANGUAGE sql AS $$
  SELECT EXISTS (SELECT 1 FROM jsonb_array_elements(p_json->'blokeringer') b WHERE b->>'art'=p_art
    AND (p_tabel IS NULL OR b->>'tabel'=p_tabel) AND (p_pk IS NULL OR b->'pk'=p_pk))
$$;
-- Test-only clone: kopier gyldige fixtures og patch nøgler/felter. Aldrig produktions-SQL.
CREATE FUNCTION pg_temp.preview_clone(p_tabel text,p_filter text,p_patch jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE j jsonb;
BEGIN
  EXECUTE format('SELECT to_jsonb(t) FROM %s t WHERE %s LIMIT 1',p_tabel,p_filter) INTO STRICT j;
  IF j IS NULL THEN RAISE EXCEPTION 'TEST_FAILED preview_clone mangler fixturrække'; END IF;
  j:=j||p_patch;
  EXECUTE format('INSERT INTO %s AS n OVERRIDING SYSTEM VALUE SELECT (jsonb_populate_record(NULL::%s,$1)).* RETURNING to_jsonb(n)',
    p_tabel,p_tabel) INTO j USING j;
  RETURN j;
END $$;
\endif
\if :g_preview
BEGIN;
\ir fixtures/kalder-matrix.sql
SELECT pg_temp.km_kaldere();
DO $role$
DECLARE k text; v_id bigint; v_error text; v_state text; v_previous text; v_prev_state text;
BEGIN
  FOREACH k IN ARRAY ARRAY['gaest','uden_profil','medlem'] LOOP
    v_previous:=NULL; v_prev_state:=NULL;
    FOREACH v_id IN ARRAY ARRAY[purge_test.id('P'),9223372036854775807::bigint] LOOP
      BEGIN
        PERFORM pg_temp.km_antal(k,format('SELECT * FROM jsonb_each(public.red_slet_person_helt_preview(%s))',v_id));
        RAISE EXCEPTION 'TEST_FAILED preview_rollegate_foerst accepterede';
      EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT,v_state=RETURNED_SQLSTATE;
      END;
      IF k='gaest' THEN
        PERFORM pg_temp.preview_assert(v_state='42501','preview_rollegate_foerst anon');
      ELSE PERFORM pg_temp.preview_assert(v_error='Kun redaktion','preview_rollegate_foerst medlem'); END IF;
      IF v_previous IS NOT NULL THEN
        PERFORM pg_temp.preview_assert(v_previous=v_error AND v_prev_state=v_state,'preview_rollegate_foerst oracle');
      END IF;
      v_previous:=v_error; v_prev_state:=v_state;
    END LOOP;
  END LOOP;
  PERFORM pg_temp.preview_assert(NOT has_function_privilege('anon','public.red_slet_person_helt_preview(bigint)','EXECUTE')
    AND NOT has_function_privilege('service_role','public.red_slet_person_helt_preview(bigint)','EXECUTE')
    AND has_function_privilege('authenticated','public.red_slet_person_helt_preview(bigint)','EXECUTE'),'preview_acl');
  PERFORM pg_temp.preview_assert(pg_temp.km_antal('redaktion',format(
    'SELECT * FROM jsonb_each(public.red_slet_person_helt_preview(%s))',purge_test.id('P')))>0,'preview_redaktion');
END $role$;
\echo OK preview_rollegate_foerst
ROLLBACK;

BEGIN;
DO $base$
DECLARE j jsonb; j_after jsonb; j_pk_only jsonb; h text; v_f bigint; v_g bigint; v_index bigint;
BEGIN
  j:=public.red_slet_person_helt_preview(purge_test.id('P'));
  PERFORM pg_temp.preview_assert(j->'blokeringer'='[]'::jsonb,'preview_fixture_ingen_blokering');
  PERFORM pg_temp.preview_assert(j->'familier_slettes' @> to_jsonb(purge_test.id('fam_del'))
    AND j->'familier_bevares' @> to_jsonb(purge_test.id('fam_keep'))
    -- Fixturens P er privat (red_opret_person): fam_keep's indhold (vielsen) slettes med P (review 37 P1+P2, løsning A).
    -- Alle kategorier (Codex-fund B); historik er et antal og kontrolleres for sig.
    AND jsonb_array_length(j->'familieindhold_slettes')=1
    AND (j->'familieindhold_slettes'->0)-'historik'=jsonb_build_object('family_id',purge_test.id('fam_keep'),
      'fakta',jsonb_build_array(purge_test.id('fakta_vielse_keep')),'noter','[]'::jsonb,'narrativer','[]'::jsonb,
      'haendelser','[]'::jsonb,'stories','[]'::jsonb,'relationer','[]'::jsonb,'forslag','[]'::jsonb)
    AND (j->'familieindhold_slettes'->0->>'historik')::int>0
    AND NOT j->'vielser_staar' @> to_jsonb(purge_test.id('fakta_vielse_keep'))
    AND NOT j->'vielser_staar' @> to_jsonb(purge_test.id('fakta_vielse_del'))
    AND j->'medier_skjules'=jsonb_build_array(purge_test.id('medie_delt')),'preview_familier');
  PERFORM pg_temp.preview_assert(j->'samme_som_komponent' @> to_jsonb(purge_test.id('nabo'))
    AND (j#>>'{historik,events}')::int>0 AND (j#>>'{historik,saet}')::int>0
    AND jsonb_array_length(j->'storage')>0 AND (j->>'levende_bruger')::boolean,'preview_indhold');
  h:=j->>'sha256';
  PERFORM pg_temp.preview_assert(h=public.red_slet_person_helt_preview(purge_test.id('P'))->>'sha256'
    AND h=encode(extensions.digest(convert_to((j-'sha256')::text,'UTF8'),'sha256'),'hex'),'preview_hash_stabil');
  -- Ét blad-faktum erstattes af et andet uden afhængige påstande; antallet er uændret.
  PERFORM purge_test.nyt(); PERFORM public.begin_change_set('preview_hash','fixture','person',purge_test.id('P'));
  INSERT INTO public.fact(subjekt_type,subjekt_id,faktatype) VALUES ('person',purge_test.id('P'),'preview-hash') RETURNING id INTO v_f;
  j:=public.red_slet_person_helt_preview(purge_test.id('P')); h:=j->>'sha256';
  DELETE FROM public.fact WHERE id=v_f;
  INSERT INTO public.fact(subjekt_type,subjekt_id,faktatype) VALUES ('person',purge_test.id('P'),'preview-hash') RETURNING id INTO v_g;
  j_after:=public.red_slet_person_helt_preview(purge_test.id('P'));
  PERFORM pg_temp.preview_assert(v_f<>v_g AND h<>j_after->>'sha256'
    AND jsonb_array_length(j#>'{steder,S13}')=jsonb_array_length(j_after#>'{steder,S13}')
    AND EXISTS (SELECT 1 FROM jsonb_array_elements(j_after#>'{steder,S13}') s
      WHERE s->>'tabel'='fact' AND s->'pk'=jsonb_build_object('id',v_g))
    AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(j_after#>'{steder,S13}') s
      WHERE s->>'tabel'='fact' AND s->'pk'=jsonb_build_object('id',v_f)),
    'preview_hash_samme_antal');
  -- Hold ALLE historikevents/-tællinger fast på efter-snapshotet; skift kun S13's pk i hashgrundlaget.
  SELECT ord-1 INTO STRICT v_index FROM jsonb_array_elements(j_after#>'{steder,S13}') WITH ORDINALITY s(j,ord)
    WHERE s.j->>'tabel'='fact' AND s.j->'pk'=jsonb_build_object('id',v_g);
  j_pk_only:=jsonb_set(j_after-'sha256',ARRAY['steder','S13',v_index::text,'pk'],jsonb_build_object('id',v_f));
  PERFORM pg_temp.preview_assert(j_after->>'sha256'=
      encode(extensions.digest(convert_to((j_after-'sha256')::text,'UTF8'),'sha256'),'hex')
    AND j_after->>'sha256'<>
      encode(extensions.digest(convert_to(j_pk_only::text,'UTF8'),'sha256'),'hex'),'preview_hash_kun_pk');
END $base$;
\echo OK preview_familier
\echo OK preview_hash_stabil
ROLLBACK;

-- §4.1: hver kolonne og måltype i sin egen rollback-subtransaktion. En baseline uden links er bevist ovenfor.
BEGIN;
DO $links$
DECLARE r record; target record; v_id bigint; v_sql text; j jsonb; v_token text;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('narrative','tekst',purge_test.id('narrativ_anden')),
    ('note','indhold',purge_test.id('note_tredje')),
    ('story','titel',purge_test.id('story_anden_forankret')),('story','tekst',purge_test.id('story_anden_forankret')),
    ('haendelse','klausul',purge_test.id('haendelse_anden_forankret')),
    ('media','titel',purge_test.id('medie_delt')),
    -- Bevaret påstand/citat hos en anden. Ikke vielsen på fam_keep: P er privat, så den slettes (review 37 P1+P2).
    ('assertion','vaerdi_tekst',(SELECT a.id FROM public.assertion a JOIN public.fact f ON a.target_type='fact' AND a.target_id=f.id
       WHERE f.subjekt_type='person' AND f.subjekt_id=purge_test.id('anden_partner') AND f.faktatype='fødsel' ORDER BY a.id LIMIT 1)),
    ('assertion','date_raw',(SELECT a.id FROM public.assertion a JOIN public.fact f ON a.target_type='fact' AND a.target_id=f.id
       WHERE f.subjekt_type='person' AND f.subjekt_id=purge_test.id('anden_partner') AND f.faktatype='fødsel' ORDER BY a.id LIMIT 1)),
    ('citation','citat_tekst',(SELECT c.id FROM public.citation c JOIN public.assertion a ON a.id=c.assertion_id
       JOIN public.fact f ON a.target_type='fact' AND a.target_id=f.id
       WHERE f.subjekt_type='person' AND f.subjekt_id=purge_test.id('anden_partner') AND f.faktatype='fødsel' ORDER BY c.id LIMIT 1))
    ) x(tabel,kolonne,id) LOOP
    FOR target IN SELECT * FROM (VALUES ('person',purge_test.id('P')),('family',purge_test.id('fam_del')),
      ('media',purge_test.id('medie_eksklusiv'))) x(typ,id) LOOP
      BEGIN
        PERFORM purge_test.nyt(); PERFORM public.begin_change_set('preview_link','fixture');
        v_token:=format('[[%s:%s|fixture]]',target.typ,target.id);
        EXECUTE format('UPDATE public.%I SET %I=$1 WHERE id=$2',r.tabel,r.kolonne) USING v_token,r.id;
        j:=public.red_slet_person_helt_preview(purge_test.id('P'));
        IF target.typ='media' AND r.tabel IN ('narrative','note') THEN
          -- trg_mentions_narrative/note synkroniserer text_mention; et medie med en indgående mention er ikke i M_del
          -- og bevares derfor. Ingen sletning → intet dødt link → ingen blokering, og mediet må ikke stå som slet.
          -- Alle arter dækkes, også text_mention med sammensat pk. Andre baselineblokeringer er irrelevante.
          PERFORM pg_temp.preview_assert(NOT EXISTS (SELECT 1 FROM jsonb_array_elements(j->'blokeringer') b WHERE
              (b->>'tabel'=r.tabel AND b->'pk'=jsonb_build_object('id',r.id))
              OR (b->>'tabel'='media' AND b->'pk'=jsonb_build_object('id',target.id))
              OR (b->>'tabel'='text_mention' AND (
                (b#>>'{pk,kilde_type}'=r.tabel AND b#>>'{pk,kilde_id}'=r.id::text)
                OR (b#>>'{pk,maal_type}'='media' AND b#>>'{pk,maal_id}'=target.id::text))))
            AND NOT EXISTS (SELECT 1 FROM private.person_purge_plan(purge_test.id('P')) pl
              WHERE pl.tabel='media' AND pl.handling='slet' AND pl.pk=jsonb_build_object('id',target.id)),
            'preview_blokering_link '||r.tabel||'.'||r.kolonne||'/media_bevares');
        ELSE
          PERFORM pg_temp.preview_assert(pg_temp.preview_has(j,'link_i_tekst',r.tabel,jsonb_build_object('id',r.id)),
            'preview_blokering_link '||r.tabel||'.'||r.kolonne||'/'||target.typ);
        END IF;
        RAISE SQLSTATE 'ZX001';
      EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL; END;
    END LOOP;
  END LOOP;
  FOR r IN SELECT unnest(ARRAY['vaerdi','note','kilde_fritekst','payload']) AS kolonne LOOP
    BEGIN
      PERFORM purge_test.nyt();
      INSERT INTO public.suggestion(subjekt_type,subjekt_id) VALUES ('person',purge_test.id('tredje')) RETURNING id INTO v_id;
      v_sql:=format('UPDATE public.suggestion SET %I=$1%s WHERE id=$2',r.kolonne,CASE WHEN r.kolonne='payload' THEN '::jsonb' ELSE '' END);
      v_token:=format('[[person:%s|fixture]]',purge_test.id('P'));
      IF r.kolonne='payload' THEN v_token:=jsonb_build_object('note',v_token)::text; END IF;
      EXECUTE v_sql USING v_token,v_id;
      PERFORM pg_temp.preview_assert(pg_temp.preview_has(public.red_slet_person_helt_preview(purge_test.id('P')),
        'link_i_tekst','suggestion',jsonb_build_object('id',v_id)),'preview_blokering_link suggestion.'||r.kolonne);
      RAISE SQLSTATE 'ZX001';
    EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL; END;
  END LOOP;
  BEGIN
    PERFORM purge_test.nyt();
    INSERT INTO public.entity_description(subjekt_type,subjekt_id,kind,tekst)
      VALUES ('person',purge_test.id('tredje'),'overview',format('[[person:%s|fixture]]',purge_test.id('P'))) RETURNING id INTO v_id;
    PERFORM pg_temp.preview_assert(pg_temp.preview_has(public.red_slet_person_helt_preview(purge_test.id('P')),
      'link_i_tekst','entity_description',jsonb_build_object('id',v_id)),'preview_blokering_link entity_description');
    RAISE SQLSTATE 'ZX001';
  EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL; END;
END $links$;
\echo OK preview_blokering_link
ROLLBACK;

BEGIN;
DO $node$
BEGIN
  -- P har allerede én samme_som (nabo). En ny person uden union med P gør P til knudepunkt (§4.6: ≥2).
  -- (tredje kan ikke bruges: tredje og P er parter i samme union, hvilket red_samme_som afviser.)
  PERFORM purge_test.nyt();
  PERFORM public.red_samme_som(public.red_opret_person('Knudepunkt Fixture','mand',false,'1860',NULL,NULL),purge_test.id('P'));
  PERFORM pg_temp.preview_assert(pg_temp.preview_has(public.red_slet_person_helt_preview(purge_test.id('P')),
    'samme_som_knudepunkt'),'preview_blokering_knudepunkt');
END $node$;
\echo OK preview_blokering_knudepunkt
ROLLBACK;

BEGIN;
DO $promotion$
DECLARE t private.interpretation%ROWTYPE; v_i uuid; v_prom uuid; j jsonb;
BEGIN
  SELECT i.* INTO STRICT t FROM private.interpretation i JOIN private.interpretation_promotion p ON p.interpretation_id=i.id
    WHERE p.id=purge_test.u('prom_egen');
  -- Ægtefællens accepterede persona, uden for X; egen record hos T1 bevares.
  PERFORM public.red_afgoer_source_persona(purge_test.u('T1'),
    (SELECT version FROM private.source_persona_identity WHERE source_persona_id=purge_test.u('T1')),
    'same',purge_test.id('aegtefaelle'),'Fixture');
  INSERT INTO private.interpretation(interpretation_key,version,source_id,source_persona_id,interpretation_kind,
    predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
  VALUES(gen_random_uuid(),1,t.source_id,purge_test.u('T1'),t.interpretation_kind,t.predicate,t.value,t.schema_version,
    t.derivation_kind,1,'proposed','fixture',t.extraction_run_id) RETURNING id INTO v_i;
  INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
    SELECT v_i,observation_id,evidence_role,ordinal FROM private.interpretation_observation WHERE interpretation_id=t.id;
  v_i:=public.red_decide_interpretation(v_i,1,'accepted','{"basis":"preview-q5"}');
  BEGIN
    INSERT INTO private.interpretation_promotion(interpretation_id,target_type,target_id,evidence,promoted_by,promoted_by_name)
    VALUES(v_i,'family',purge_test.id('fam_del'),jsonb_build_object('state_sha256',repeat('a',64)),auth.uid(),'Fixture') RETURNING id INTO v_prom;
    PERFORM pg_temp.preview_assert(pg_temp.preview_has(public.red_slet_person_helt_preview(purge_test.id('P')),
      'anden_promotion','private.interpretation_promotion',jsonb_build_object('id',v_prom)),'preview_blokering_promotion');
    RAISE SQLSTATE 'ZX001';
  EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL; END;
  INSERT INTO private.interpretation_promotion(interpretation_id,target_type,target_id,evidence,promoted_by,promoted_by_name)
    VALUES(v_i,'person',purge_test.id('P'),'{"basis":"preview-q5"}',auth.uid(),'Fixture') RETURNING id INTO v_prom;
  j:=public.red_slet_person_helt_preview(purge_test.id('P'));
  PERFORM pg_temp.preview_assert(NOT pg_temp.preview_has(j,'anden_promotion') AND EXISTS (
    SELECT 1 FROM jsonb_array_elements(j#>'{steder,S39a}') p WHERE p->'pk'=jsonb_build_object('id',v_prom)),
    'preview_ingen_blokering_egen_promotion_fra_andens_record');
END $promotion$;
\echo OK preview_blokering_promotion
\echo OK preview_ingen_blokering_egen_promotion_fra_andens_record
ROLLBACK;

-- Ny kontrolkørsel pr. vej/status; den gamle failed-kørsel ændres aldrig.
BEGIN;
DO $control$
DECLARE v_run uuid; v_cr uuid; v_j jsonb; v_path int; v_status text; v_row jsonb;
BEGIN
  FOR v_path IN 1..6 LOOP
    FOREACH v_status IN ARRAY ARRAY['sealed','passed','failed'] LOOP
      BEGIN
        v_run:=gen_random_uuid(); v_cr:=gen_random_uuid();
        PERFORM pg_temp.preview_clone('private.source_persona_identity_candidate_run',format('id=%L',purge_test.u('kandidatkoersel')),
          jsonb_build_object('id',v_cr,'run_seq',(SELECT max(run_seq)+1 FROM private.source_persona_identity_candidate_run),
            'input_sha256',encode(extensions.digest(v_cr::text,'sha256'),'hex')));
        PERFORM pg_temp.preview_clone('private.identity_control_run',format('id=%L',purge_test.u('kontrolkoersel')),
          jsonb_build_object('id',v_run,'candidate_run_id',v_cr));
        IF v_path=1 THEN
          PERFORM pg_temp.preview_clone('private.identity_control_sample',format('id=%L',purge_test.u('stikproeve_X1')),
            jsonb_build_object('id',gen_random_uuid(),'control_run_id',v_run,'mapping','{"1":"S"}'::jsonb,'expected','S'));
        ELSIF v_path=2 THEN -- P kun som mapping/expected i en ANDENS stikprøve.
          PERFORM pg_temp.preview_clone('private.identity_control_sample',format('id=%L',purge_test.u('stikproeve_X1')),
            jsonb_build_object('id',gen_random_uuid(),'control_run_id',v_run,'source_persona_id',purge_test.u('T1')));
        ELSIF v_path=3 THEN
          INSERT INTO private.identity_control_exclusion VALUES(v_run,purge_test.u('X1'),'rang1_tidsumulig');
        ELSIF v_path=4 THEN -- counterpart uden P i partner_ids, så vejene prøves uafhængigt.
          PERFORM pg_temp.preview_clone('private.identity_control_parent_card','true',jsonb_build_object('id',gen_random_uuid(),
            'control_run_id',v_run,'family_id',purge_test.id('fam_andre'),'partner_ids',ARRAY[purge_test.id('tredje')]));
        ELSIF v_path=5 THEN
          PERFORM pg_temp.preview_clone('private.identity_control_parent_card','true',jsonb_build_object('id',gen_random_uuid(),
            'control_run_id',v_run,'counterpart_person_id',purge_test.id('tredje')));
        ELSE
          PERFORM pg_temp.preview_clone('private.source_persona_identity_candidate',format('id=%L',purge_test.u('kandidat_P')),
            jsonb_build_object('id',gen_random_uuid(),'run_id',v_cr));
        END IF;
        PERFORM private.append_control_event(v_run,'sealed',NULL,repeat('1',64),repeat('2',64));
        IF v_status<>'sealed' THEN PERFORM private.append_control_event(v_run,v_status,NULL); END IF;
        v_j:=public.red_slet_person_helt_preview(purge_test.id('P'));
        PERFORM pg_temp.preview_assert(pg_temp.preview_has(v_j,'aaben_koersel','private.identity_control_run',jsonb_build_object('id',v_run))
          =(v_status='sealed'),'preview_blokering_aaben_koersel');
        IF v_status='passed' THEN
          PERFORM pg_temp.preview_assert(EXISTS(SELECT 1 FROM jsonb_array_elements(v_j->'advarsler') a
            WHERE a->>'art'='kontrolkoersel_failer' AND a->>'control_run_id'=v_run::text),'preview_q4');
        END IF;
        RAISE SQLSTATE 'ZX001';
      EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL; END;
    END LOOP;
  END LOOP;
END $control$;
\echo OK preview_blokering_aaben_koersel
ROLLBACK;

BEGIN;
DO $batches$
DECLARE v_case int; a jsonb; b jsonb; c jsonb; e jsonb; v_a uuid; v_b uuid; v_child uuid; v_new_b uuid; j jsonb;
BEGIN
  FOR v_case IN 1..7 LOOP
    BEGIN
      v_a:=gen_random_uuid(); v_b:=gen_random_uuid();
      IF v_case IN (1,2,3,4,7) THEN
        a:=pg_temp.preview_clone('private.reimport_authorization',format('id=(SELECT authorization_id FROM private.reimport_batch WHERE id=%L)',
          purge_test.u('nc_forælder')),jsonb_build_object('id',v_a,'nonce',gen_random_uuid(),
          'status',CASE WHEN v_case IN (3,4) THEN 'issued' ELSE 'consumed' END,
          'consumed_at',CASE WHEN v_case IN (3,4) THEN NULL ELSE to_jsonb(now()) END,
          'expires_at',now()+CASE WHEN v_case=4 THEN interval '-1 day' ELSE interval '1 day' END));
      ELSE
        a:=pg_temp.preview_clone('private.reimport_case_authorization','true',jsonb_build_object('id',v_a,'nonce',gen_random_uuid(),
          'status',CASE WHEN v_case=6 THEN 'issued' ELSE 'consumed' END,
          'consumed_at',CASE WHEN v_case=6 THEN NULL ELSE to_jsonb(now()) END));
      END IF;
      IF v_case IN (1,2) THEN
        b:=pg_temp.preview_clone('private.reimport_batch',format('id=%L',purge_test.u('nc_forælder')),
          jsonb_build_object('id',v_b,'authorization_id',v_a,'preview_sha256',encode(extensions.digest(v_b::text,'sha256'),'hex'),
            'status',CASE WHEN v_case=1 THEN 'open' ELSE 'finalized' END));
        IF v_case=2 THEN
          e:=pg_temp.preview_clone('private.reimport_event',format('batch_id=%L AND operation=%L',purge_test.u('nc_forælder'),'person_create'),
            jsonb_build_object('id',nextval(pg_get_serial_sequence('private.reimport_event','id')),'batch_id',v_b));
          v_a:=gen_random_uuid(); v_child:=gen_random_uuid();
          a:=pg_temp.preview_clone('private.reimport_authorization',format('id=(SELECT authorization_id FROM private.reimport_batch WHERE id=%L)',
            purge_test.u('nc_barn')),jsonb_build_object('id',v_a,'nonce',gen_random_uuid(),
            'authorized_elements',jsonb_build_object('source_batch_id',v_b)));
          c:=pg_temp.preview_clone('private.reimport_batch',format('id=%L',purge_test.u('nc_barn')),
            jsonb_build_object('id',v_child,'authorization_id',v_a,'preview_sha256',encode(extensions.digest(v_child::text,'sha256'),'hex')));
        END IF;
      ELSIF v_case=5 THEN
        b:=pg_temp.preview_clone('private.reimport_case_batch','true',jsonb_build_object('id',v_b,'authorization_id',v_a,'status','open',
          'preview_sha256',encode(extensions.digest(v_b::text,'sha256'),'hex')));  -- manifest_uidx kræver en ny preview-hash
      ELSIF v_case=7 THEN
        -- En ny B har to subjekter (P og tredje), men dens eneste C-event er P's.
        b:=pg_temp.preview_clone('private.reimport_batch',format('id=%L',purge_test.u('b_batch')),
          jsonb_build_object('id',v_b,'authorization_id',v_a,'preview_sha256',encode(extensions.digest(v_b::text,'sha256'),'hex')));
        FOR e IN SELECT to_jsonb(t) AS j FROM private.reimport_event t WHERE batch_id=purge_test.u('b_batch') LOOP
          -- B-events er kun nødvendige som population for den reelle venter-på-kontrol-vej.
          PERFORM pg_temp.preview_clone('private.reimport_event',format('id=%s',e->>'id'),
            jsonb_build_object('id',nextval(pg_get_serial_sequence('private.reimport_event','id')),'batch_id',v_b));
        END LOOP;
        v_new_b:=v_b; v_a:=gen_random_uuid(); v_b:=gen_random_uuid();
        a:=pg_temp.preview_clone('private.reimport_authorization',format('id=(SELECT authorization_id FROM private.reimport_batch WHERE id=%L)',
          purge_test.u('c_batch')),jsonb_build_object('id',v_a,'nonce',gen_random_uuid()));
        b:=pg_temp.preview_clone('private.reimport_batch',format('id=%L',purge_test.u('c_batch')),
          jsonb_build_object('id',v_b,'authorization_id',v_a,'preview_sha256',encode(extensions.digest(v_b::text,'sha256'),'hex')));
        SELECT to_jsonb(t) INTO e FROM private.reimport_event t WHERE batch_id=purge_test.u('c_batch') AND canonical_person_id=purge_test.id('P');
        PERFORM pg_temp.preview_clone('private.reimport_event',format('id=%s',e->>'id'),
          jsonb_build_object('id',nextval(pg_get_serial_sequence('private.reimport_event','id')),'batch_id',v_b,
            'payload',(e->'payload')||jsonb_build_object('persona_batch_id',v_new_b)));
      END IF;
      j:=public.red_slet_person_helt_preview(purge_test.id('P'));
      IF v_case=4 THEN
        PERFORM pg_temp.preview_assert(NOT pg_temp.preview_has(j,'aaben_batch','private.reimport_authorization',jsonb_build_object('id',v_a)),
          'preview_udloebet_autorisation');
      ELSE
        PERFORM pg_temp.preview_assert(pg_temp.preview_has(j,'aaben_batch',CASE
          WHEN v_case=3 THEN 'private.reimport_authorization' WHEN v_case=6 THEN 'private.reimport_case_authorization'
          WHEN v_case=5 THEN 'private.reimport_case_batch' ELSE 'private.reimport_batch' END,
          jsonb_build_object('id',CASE WHEN v_case IN (3,6) THEN v_a WHEN v_case=7 THEN v_new_b ELSE v_b END)),
          'preview_blokering_batch');
        IF v_case=2 THEN PERFORM pg_temp.preview_assert(pg_temp.preview_has(j,'aaben_batch','private.reimport_batch',
          jsonb_build_object('id',v_child)),'preview_blokering_name_completion_barn'); END IF;
      END IF;
      RAISE SQLSTATE 'ZX001';
    EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL; END;
  END LOOP;
END $batches$;
\echo OK preview_blokering_batch
ROLLBACK;

BEGIN;
DO $awaiting$
DECLARE v_a uuid; v_b uuid:=purge_test.u('c_batch'); j jsonb;
BEGIN
  PERFORM purge_test.nyt();
  SET LOCAL ROLE service_role;
  v_a:=public.red_authorize_reimport_reversal(v_b,gen_random_uuid(),now()+interval '10 minutes');
  SET LOCAL ROLE authenticated;
  PERFORM public.red_reverse_reimport_publication(v_b,v_a);
  RESET ROLE;
  j:=public.red_slet_person_helt_preview(purge_test.id('P'));
  PERFORM pg_temp.preview_assert(pg_temp.preview_has(j,'afventer_kontrol','private.source_persona',
    jsonb_build_object('id',purge_test.u('X1'))),'preview_blokering_afventer_kontrol');
END $awaiting$;
\echo OK preview_blokering_afventer_kontrol
ROLLBACK;
BEGIN;
DO $assertion$
DECLARE v_typ text; v_a bigint;
BEGIN
  FOREACH v_typ IN ARRAY ARRAY['person','family'] LOOP
    BEGIN
      PERFORM purge_test.nyt(); PERFORM public.begin_change_set('preview_paastand','fixture');
      INSERT INTO public.assertion(target_type,target_id,objekt_type,objekt_id)
        SELECT 'fact',id,v_typ,CASE WHEN v_typ='person' THEN purge_test.id('P') ELSE purge_test.id('fam_del') END
        FROM public.fact WHERE subjekt_type='person' AND subjekt_id=purge_test.id('tredje') LIMIT 1 RETURNING id INTO STRICT v_a;
      PERFORM pg_temp.preview_assert(pg_temp.preview_has(public.red_slet_person_helt_preview(purge_test.id('P')),
        'anden_paastand','assertion',jsonb_build_object('id',v_a)),'preview_blokering_anden_paastand');
      RAISE SQLSTATE 'ZX001';
    EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL; END;
  END LOOP;
END $assertion$;
\echo OK preview_blokering_anden_paastand
ROLLBACK;

BEGIN;
CREATE TEMP TABLE q9_expected(sted text,tabel text,pk jsonb,PRIMARY KEY(sted,tabel,pk)) ON COMMIT DROP;
DO $q9$
DECLARE v_name text; v_id bigint; v_uuid uuid; j jsonb; v_card uuid; v_i uuid; v_e bigint;
  v_obs private.source_observation%ROWTYPE; v_prev private.source_observation_text%ROWTYPE; v_rend uuid;
BEGIN
  SELECT visning_navn INTO STRICT v_name FROM public.person WHERE id=purge_test.id('P');
  -- S38b (bevarede familiers fritekst) gælder kun en offentlig P: er P ikke-offentlig, slettes fam_keep's indhold
  -- (review 37 P1+P2, løsning A). Kun i denne rollback-transaktion.
  UPDATE public.person SET privat=false WHERE id=purge_test.id('P');
  PERFORM purge_test.nyt(); PERFORM public.begin_change_set('preview_q9','fixture');
  UPDATE public.note SET indhold=v_name WHERE id=purge_test.id('note_tredje');
  INSERT INTO q9_expected VALUES('S58','note',jsonb_build_object('id',purge_test.id('note_tredje')));
  UPDATE public.media SET titel=v_name WHERE id=purge_test.id('medie_delt');
  INSERT INTO q9_expected VALUES('S37b','media',jsonb_build_object('id',purge_test.id('medie_delt')));
  INSERT INTO public.suggestion(subjekt_type,subjekt_id,note) VALUES('person',purge_test.id('tredje'),v_name) RETURNING id INTO v_id;
  INSERT INTO q9_expected VALUES('S34b','suggestion',jsonb_build_object('id',v_id));
  INSERT INTO public.note(target_type,target_id,indhold) VALUES('family',purge_test.id('fam_keep'),v_name) RETURNING id INTO v_id;
  INSERT INTO q9_expected VALUES('S38b','note',jsonb_build_object('id',v_id));
  INSERT INTO public.narrative(subjekt_type,subjekt_id,tekst) VALUES('family',purge_test.id('fam_keep'),v_name) RETURNING id INTO v_id;
  INSERT INTO q9_expected VALUES('S38b','narrative',jsonb_build_object('id',v_id));
  -- Fixturens P er privat, så vielsen på fam_keep slettes (review 37 P1+P2); S38b prøves på et faktum, der står.
  PERFORM purge_test.nyt();
  j:=public.red_opret_fakta('family',purge_test.id('fam_keep'),'skilsmisse','1890',p_kilde_fritekst=>'Syntetisk kilde');
  PERFORM purge_test.nyt(); PERFORM public.begin_change_set('preview_q9_familie','fixture');
  UPDATE public.assertion SET vaerdi_tekst=v_name WHERE target_type='fact' AND target_id=(j->>'fact_id')::bigint RETURNING id INTO STRICT v_id;
  INSERT INTO q9_expected VALUES('S38b','assertion',jsonb_build_object('id',v_id));
  UPDATE public.citation SET citat_tekst=v_name WHERE assertion_id=v_id RETURNING id INTO STRICT v_id;
  INSERT INTO q9_expected VALUES('S38b','citation',jsonb_build_object('id',v_id));
  j:=pg_temp.preview_clone('private.reimport_case_authorization','true',jsonb_build_object('id',gen_random_uuid(),
    'nonce',gen_random_uuid(),'authorized_elements',jsonb_build_object('note',v_name)));
  INSERT INTO q9_expected VALUES('S44b','private.reimport_case_authorization',jsonb_build_object('id',j->'id'));
  v_card:=gen_random_uuid();
  PERFORM pg_temp.preview_clone('private.identity_control_parent_card','true',jsonb_build_object('id',v_card,
    'interpretation_key',gen_random_uuid(),'counterpart_person_id',purge_test.id('tredje')));
  PERFORM private.append_parent_card_event(v_card,'F',v_name,jsonb_build_object('sheet_sha256',repeat('1',64),'rows_sha256',repeat('2',64),'line',1));
  INSERT INTO q9_expected VALUES('S45b','private.identity_control_parent_event',jsonb_build_object('card_id',v_card,'seq',1));
  SELECT interpretation_id INTO STRICT v_i FROM private.interpretation_promotion WHERE id=purge_test.u('prom_egen');
  INSERT INTO private.marriage_ordinal_correction(interpretation_key,interpretation_id,party_version_from,party_version_to,
    ordinal_from,ordinal_to,family_id,evidence,created_by)
    VALUES(gen_random_uuid(),v_i,1,2,1,2,purge_test.id('fam_keep'),jsonb_build_object('note',v_name),auth.uid()) RETURNING id INTO v_uuid;
  INSERT INTO q9_expected VALUES('S49c','private.marriage_ordinal_correction',jsonb_build_object('id',v_uuid));
  j:=pg_temp.preview_clone('private.interpretation',format('id=%L',v_i),jsonb_build_object('id',gen_random_uuid(),
    'interpretation_key',gen_random_uuid(),'version',1,'supersedes_id',NULL,'status','proposed',
    'source_persona_id',purge_test.u('T1'),'value',jsonb_build_object('note',v_name),
    'decided_by',NULL,'decided_by_name',NULL,'decided_at',NULL));  -- proposed kræver tomme afgørelsesfelter
  INSERT INTO q9_expected VALUES('S58','private.interpretation',jsonb_build_object('id',j->'id'));
  -- Y bevares. En ny rigtig afgørelse med fritekst giver en bevaret v3-event.
  PERFORM public.red_afgoer_source_persona(purge_test.u('Y'),2,'same',purge_test.id('tredje'),v_name);
  INSERT INTO q9_expected SELECT 'S11c','private.source_persona_identity_event',jsonb_build_object('id',id)
    FROM private.source_persona_identity_event WHERE source_persona_id=purge_test.u('Y') AND version=3;
  -- R28's nye bog-redaktørfelter. Original bogtekst hverken opdateres eller returneres.
  PERFORM private.append_control_event(purge_test.u('kontrolkoersel'),'failed',v_name);
  INSERT INTO q9_expected SELECT 'S58','private.identity_control_event',jsonb_build_object('control_run_id',control_run_id,'seq',seq)
    FROM private.identity_control_event WHERE control_run_id=purge_test.u('kontrolkoersel') ORDER BY seq DESC LIMIT 1;
  SELECT to_jsonb(t) INTO STRICT j FROM private.source_record_anchor_event t WHERE source_record_id=purge_test.u('record_P') ORDER BY version DESC LIMIT 1;
  j:=pg_temp.preview_clone('private.source_record_anchor_event',format('id=%L',j->>'id'),jsonb_build_object('id',gen_random_uuid(),
    'version',(j->>'version')::int+1,'decision_status','proposed','evidence',jsonb_build_object('note',v_name)));
  INSERT INTO q9_expected VALUES('S58','private.source_record_anchor_event',jsonb_build_object('id',j->'id'));
  INSERT INTO private.source_record_revision_event(predecessor_record_id,successor_record_id,relation_kind,decision_status,evidence,version)
    SELECT purge_test.u('record_P'),r.id,'replaced_by','proposed',jsonb_build_object('note',v_name),1
    FROM private.source_record r WHERE r.source_id=purge_test.id('kilde_a') AND r.id<>purge_test.u('record_P')
      AND NOT EXISTS (SELECT 1 FROM private.source_record_revision_event e WHERE e.predecessor_record_id=purge_test.u('record_P')
        AND e.successor_record_id=r.id AND e.relation_kind='replaced_by') LIMIT 1 RETURNING id INTO STRICT v_uuid;
  INSERT INTO q9_expected VALUES('S58','private.source_record_revision_event',jsonb_build_object('id',v_uuid));
  SELECT o.* INTO STRICT v_obs FROM private.source_observation o ORDER BY id LIMIT 1;
  SELECT rendition_id INTO STRICT v_rend FROM private.source_record_occurrence WHERE id=v_obs.occurrence_id;
  SELECT * INTO v_prev FROM private.source_observation_text WHERE observation_id=v_obs.id AND rendition_id=v_rend ORDER BY version DESC LIMIT 1;
  INSERT INTO private.source_observation_text(observation_id,rendition_id,version,verbatim_text,char_from,char_to,supersedes_id,evidence)
    VALUES(v_obs.id,v_rend,coalesce(v_prev.version,0)+1,v_obs.verbatim_text,v_obs.char_from,v_obs.char_to,v_prev.id,
      jsonb_build_object('note',v_name)) RETURNING id INTO v_uuid;
  INSERT INTO q9_expected VALUES('S58','private.source_observation_text',jsonb_build_object('id',v_uuid));
  PERFORM purge_test.nyt(); PERFORM public.begin_change_set('preview_q9_description','fixture');
  INSERT INTO public.entity_description(subjekt_type,subjekt_id,kind,tekst) VALUES('person',purge_test.id('tredje'),'overview','Fixture') RETURNING id INTO v_id;
  INSERT INTO private.entity_description_source VALUES(v_id,purge_test.u('record_P'),v_name);
  INSERT INTO q9_expected VALUES('S58','private.entity_description_source',jsonb_build_object('description_id',v_id,'source_record_id',purge_test.u('record_P')));
  -- exclusion.reason er lukket vokabular: kan_ikke_forekomme-listen i Task 2b-harnessen dokumenterer dette.
  PERFORM pg_temp.preview_assert(EXISTS(SELECT 1 FROM pg_constraint WHERE conrelid='private.identity_control_exclusion'::regclass
    AND pg_get_constraintdef(oid) LIKE '%rang1_tidsumulig%' AND pg_get_constraintdef(oid) LIKE '%navnefaeller_over_3%'),
    'preview_q9_exclusion_kan_ikke_forekomme');
  j:=public.red_slet_person_helt_preview(purge_test.id('P'));
  PERFORM pg_temp.preview_assert(NOT EXISTS(SELECT 1 FROM q9_expected e WHERE NOT EXISTS(
    SELECT 1 FROM jsonb_array_elements(j->'til_kontrol') k WHERE k->>'sted'=e.sted AND k->>'tabel'=e.tabel AND k->'pk'=e.pk)),
    'preview_til_kontrol');
  PERFORM pg_temp.preview_assert(position(v_name IN (j-'navn')::text)=0
    AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(j->'til_kontrol') k
      WHERE (SELECT array_agg(key ORDER BY key COLLATE "C") FROM jsonb_object_keys(k) key)
        IS DISTINCT FROM ARRAY['grund','pk','sted','tabel']::text[]),'preview_ingen_fritekst');
END $q9$;
\echo OK preview_til_kontrol
\echo OK preview_ingen_fritekst
ROLLBACK;

-- Q9: navnet står kun i JSON og indeholder hverken P's id eller et familie-id.
BEGIN;
DO $q9_escaped$
DECLARE v_name text; v_id bigint; j jsonb;
BEGIN
  FOREACH v_name IN ARRAY ARRAY[$name$Purge "Citat"$name$,$name$Purge \Streg$name$] LOOP
    BEGIN
      PERFORM purge_test.nyt(); PERFORM public.begin_change_set('preview_q9_escaped','fixture');
      UPDATE public.person SET visning_navn=v_name WHERE id=purge_test.id('P');
      INSERT INTO public.suggestion(subjekt_type,subjekt_id,payload)
        VALUES('person',purge_test.id('tredje'),jsonb_build_object('note',v_name)) RETURNING id INTO v_id;
      -- Bevis, at den uescapede søgning ikke ville finde testnavnet.
      PERFORM pg_temp.preview_assert(NOT EXISTS (SELECT 1 FROM public.suggestion s WHERE s.id=v_id
        AND position((v_name COLLATE "C") IN (s.payload::text COLLATE "C"))>0),'preview_q9_escape_fixture');
      j:=public.red_slet_person_helt_preview(purge_test.id('P'));
      PERFORM pg_temp.preview_assert(EXISTS (SELECT 1 FROM jsonb_array_elements(j->'til_kontrol') k
        WHERE k->>'sted'='S34b' AND k->>'tabel'='suggestion' AND k->'pk'=jsonb_build_object('id',v_id)),
        'preview_q9_json_escaped');
      RAISE SQLSTATE 'ZX001';
    EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL; END;
  END LOOP;
END $q9_escaped$;
\echo OK preview_q9_json_escaped
ROLLBACK;
\endif

\if :g_preview_q3
SET request.jwt.claim.sub='a2a00000-0000-4000-8000-00000000a001';
\ir fixtures/person-purge-reimport.sql
BEGIN;
CREATE TEMP TABLE preview_chain(state jsonb,haendelse_id bigint) ON COMMIT DROP;
CREATE FUNCTION pg_temp.preview_q3(p_person bigint,p_batch uuid,p_vej text,p_niveau text) RETURNS boolean LANGUAGE sql AS $$
  SELECT CASE WHEN p_niveau IS NULL THEN NOT EXISTS (
    SELECT 1 FROM jsonb_array_elements(public.red_slet_person_helt_preview(p_person)->'advarsler') a
    WHERE a->>'art'='fortrydelse_mistes' AND a->>'batch_id'=p_batch::text AND a->>'vej'=p_vej)
  ELSE EXISTS(SELECT 1 FROM jsonb_array_elements(public.red_slet_person_helt_preview(p_person)->'advarsler') a
    WHERE a->>'art'='fortrydelse_mistes' AND a->>'batch_id'=p_batch::text AND a->>'vej'=p_vej AND a->>'niveau'=p_niveau) END
$$;
-- Positiv RPC med deferred constraints; en succes rulles tilbage, øvrige fejl propagere.
CREATE FUNCTION pg_temp.preview_reverse_ok(p_batch uuid,p_publication boolean,p_count int DEFAULT NULL) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_a uuid; v_res jsonb;
BEGIN
  BEGIN
    PERFORM purge_test.nyt();
    SET LOCAL ROLE service_role;
    v_a:=public.red_authorize_reimport_reversal(p_batch,gen_random_uuid(),now()+interval '10 minutes');
    SET LOCAL ROLE authenticated;
    IF p_publication THEN v_res:=public.red_reverse_reimport_publication(p_batch,v_a);
    ELSE v_res:=public.red_reverse_reimport(p_batch,v_a); END IF;
    RESET ROLE;
    PERFORM pg_temp.preview_assert(v_res->>'status'='reversed' AND (p_count IS NULL OR (v_res->>'reversed_identities')::int=p_count),
      'preview_q3_rpc_kvittering');
    SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
    RAISE SQLSTATE 'ZX001';
  EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL; END;
END $$;
DO $setup$
DECLARE v_s bigint:=nextval(pg_get_serial_sequence('public.source','id')); j jsonb; v_n bigint; v_h bigint; v_a uuid;
BEGIN
  PERFORM purge_test.nyt();
  j:=pg_temp.purge_complete_profile(pg_temp.purge_stage_profile(v_s,'preview-q3','PREVIEW-Q3','Purge Q',v_s));
  SELECT narrative_id INTO STRICT v_n FROM private.narrative_record_publication WHERE source_record_id=(j->>'source_record_id')::uuid AND status='draft';
  PERFORM purge_test.nyt();  -- som Task 4's fortrydelse_generel: friskt sæt til hændelsen
  INSERT INTO public.haendelse(subjekt_type,subjekt_id,narrative_id,noegle,klausul)
    VALUES('person',purge_test.id('P'),v_n,'preview-q3-s26','Fixture') RETURNING id INTO v_h;
  v_a:=public.red_authorize_reimport_cutover((j->>'source_batch_id')::uuid,gen_random_uuid(),now()+interval '10 minutes');
  PERFORM public.red_activate_reimport_batch((j->>'source_batch_id')::uuid,v_a);
  INSERT INTO preview_chain VALUES(j,v_h);
END $setup$;
DO $last$
DECLARE j jsonb; v_b uuid; v_q bigint; v_h bigint; v_vej text; p jsonb; v_a uuid; v_error text;
BEGIN
  SELECT state,(state->>'source_batch_id')::uuid,(state->>'person_id')::bigint,haendelse_id INTO STRICT j,v_b,v_q,v_h FROM preview_chain;
  PERFORM pg_temp.preview_reverse_ok(v_b,false);
  FOREACH v_vej IN ARRAY ARRAY['red_reverse_reimport','red_reverse_1939_v50_reimport'] LOOP
    PERFORM pg_temp.preview_assert(pg_temp.preview_q3(purge_test.id('P'),v_b,v_vej,'advarsel'),'preview_s26_sidste_advarsel');
    -- Den generelle batch har KUN Q og Q's persona (X når Q slettes). Ingen subjekt uden for X mister noget.
    PERFORM pg_temp.preview_assert(pg_temp.preview_q3(v_q,v_b,v_vej,'note'),'preview_generel_p_only_note');
  END LOOP;
  p:=public.red_slet_person_helt_preview(v_q);
  PERFORM pg_temp.preview_assert(NOT pg_temp.preview_has(p,'aaben_batch'),'preview_ingen_blokering_aktiveret_batch');
  -- Reel fjernelse af sidste hændelse bryder receiptet for Q og dermed den generelle RPC.
  BEGIN
    DELETE FROM public.haendelse WHERE id=v_h;
    SET LOCAL ROLE service_role;
    v_a:=public.red_authorize_reimport_reversal(v_b,gen_random_uuid(),now()+interval '10 minutes');
    RESET ROLE;
    BEGIN
      SET LOCAL ROLE authenticated; PERFORM public.red_reverse_reimport(v_b,v_a); RESET ROLE;
      RAISE EXCEPTION 'TEST_FAILED preview_s26_sidste_rpc';
    EXCEPTION WHEN raise_exception THEN GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
      IF v_error IS DISTINCT FROM 'REIMPORT_WRITER_REVERSAL_INVALID' THEN RAISE; END IF;
    END;
    RAISE SQLSTATE 'ZX001';
  EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL; END;
END $last$;
\echo OK preview_s26_sidste_advarsel
\echo OK preview_generel_p_only_note
\echo OK preview_ingen_blokering_aktiveret_batch

DO $unchanged$
DECLARE j jsonb; v_b uuid; v_q bigint; v_h bigint; v_n bigint; v_mode int; v_before jsonb; v_after jsonb; v_vej text;
BEGIN
  SELECT state,(state->>'source_batch_id')::uuid,(state->>'person_id')::bigint,haendelse_id INTO STRICT j,v_b,v_q,v_h FROM preview_chain;
  SELECT narrative_id INTO STRICT v_n FROM public.haendelse WHERE id=v_h;
  FOR v_mode IN 1..2 LOOP
    BEGIN
      IF v_mode=1 THEN -- S26 fjernes, men en ANDEN hændelse bevares: has_haendelse forbliver true.
        INSERT INTO public.haendelse(subjekt_type,subjekt_id,narrative_id,noegle,klausul)
          VALUES('person',v_q,v_n,'preview-q3-kept','Fixture');
      ELSE -- Ren S27: hændelsen er Q's; kun dens binding til P's faktum forsvinder.
        UPDATE public.haendelse SET subjekt_id=v_q,fact_id=purge_test.id('fakta_titel') WHERE id=v_h;
        PERFORM pg_temp.preview_assert(EXISTS(SELECT 1 FROM private.person_purge_plan(purge_test.id('P'))
          WHERE tabel='haendelse' AND pk=jsonb_build_object('id',v_h) AND sted='S27' AND handling='loesn'),'preview_s27_fixture');
      END IF;
      FOREACH v_vej IN ARRAY ARRAY['red_reverse_reimport','red_reverse_1939_v50_reimport'] LOOP
        PERFORM pg_temp.preview_assert(pg_temp.preview_q3(purge_test.id('P'),v_b,v_vej,NULL),'preview_uændret_ingen_post');
      END LOOP;
      v_before:=private.narrative_record_state(v_q,(j->>'source_id')::bigint,j#>>'{person_payload,source_record_key}',false);
      IF v_mode=1 THEN DELETE FROM public.haendelse WHERE id=v_h;
      ELSE UPDATE public.haendelse SET fact_id=NULL,relation_id=NULL WHERE id=v_h; END IF;
      v_after:=private.narrative_record_state(v_q,(j->>'source_id')::bigint,j#>>'{person_payload,source_record_key}',false);
      PERFORM pg_temp.preview_assert(v_before=v_after,'preview_s26_s27_state_uaendret');
      PERFORM pg_temp.preview_reverse_ok(v_b,false);
      RAISE SQLSTATE 'ZX001';
    EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL; END;
  END LOOP;
END $unchanged$;
\echo OK preview_s26_bevaret_haendelse_ingen_post
\echo OK preview_s27_ingen_post_rpc_virker

DO $unrelated_history$
DECLARE j jsonb; v_b uuid; v_q bigint; v_h bigint; v_n bigint; v_binding uuid; v_event uuid; v_vej text;
  v_before jsonb; v_after jsonb; v_plan jsonb; v_receipt jsonb;
BEGIN
  BEGIN
    SELECT state,(state->>'source_batch_id')::uuid,(state->>'person_id')::bigint,haendelse_id
      INTO STRICT j,v_b,v_q,v_h FROM preview_chain;
    -- S26 må ikke være en anden grund til tab i denne prøve; has_haendelse ændres ikke.
    UPDATE public.haendelse SET subjekt_id=v_q WHERE id=v_h;
    v_before:=private.narrative_record_state(v_q,(j->>'source_id')::bigint,j#>>'{person_payload,source_record_key}',false);
    SELECT payload->'post_activation_receipts'->v_q::text INTO STRICT v_receipt
      FROM private.reimport_event WHERE batch_id=v_b AND operation='activation';
    PERFORM pg_temp.preview_assert(v_before->>'state_sha256'=v_receipt->>'state_sha256','preview_q3_historik_receipt');
    -- Historisk P-binding på Q's record. Som grundfixturens S23-ledger bygges den direkte med aktive validatorer.
    PERFORM purge_test.nyt(); PERFORM public.begin_change_set('preview_q3_historik','fixture','person',purge_test.id('P'));
    INSERT INTO public.narrative(subjekt_type,subjekt_id,source_id,tekst)
      VALUES('person',purge_test.id('P'),(j->>'source_id')::bigint,'Fixture') RETURNING id INTO v_n;
    INSERT INTO private.narrative_record_publication(narrative_id,source_record_id,record_label,citation_label,status,created_at)
      VALUES(v_n,(j->>'source_record_id')::uuid,'Fixture','Fixture','withdrawn',now()-interval '1 day') RETURNING id INTO v_binding;
    INSERT INTO private.narrative_publication_event(change_set_id,stream_ref,stream_version,event_type,binding_id,narrative_id,
      source_id,source_record_id,decision_basis,before_state,after_state,before_state_sha256,after_state_sha256,decided_by,decided_by_name)
      VALUES(purge_test.saet(),v_binding,1,'draft_discarded',v_binding,v_n,(j->>'source_id')::bigint,
        (j->>'source_record_id')::uuid,'Fixture','{}','{}',encode(extensions.digest('{}','sha256'),'hex'),
        encode(extensions.digest('{}','sha256'),'hex'),auth.uid(),'Fixture') RETURNING id INTO v_event;
    v_after:=private.narrative_record_state(v_q,(j->>'source_id')::bigint,j#>>'{person_payload,source_record_key}',false);
    PERFORM pg_temp.preview_assert(v_before=v_after,'preview_q3_fremmed_historik_state');
    SELECT jsonb_agg(to_jsonb(p)) INTO v_plan FROM private.person_purge_plan(purge_test.id('P')) p;
    PERFORM pg_temp.preview_assert(EXISTS (SELECT 1 FROM jsonb_array_elements(v_plan) p WHERE
        p->>'tabel'='private.narrative_record_publication' AND p->>'handling'='slet' AND p->'pk'=jsonb_build_object('id',v_binding))
      AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_plan) p WHERE
        p->>'tabel'='private.narrative_publication_event' AND p->>'handling'='slet' AND p->'pk'=jsonb_build_object('id',v_event)),
      'preview_q3_fremmed_historik_plan');
    FOREACH v_vej IN ARRAY ARRAY['red_reverse_reimport','red_reverse_1939_v50_reimport'] LOOP
      -- ready=true forhindrer, at »ingen post« blot skyldes en allerede defekt fixture.
      PERFORM pg_temp.preview_assert(EXISTS (SELECT 1 FROM private.person_purge_fortrydelse(purge_test.id('P'),v_plan) f
        WHERE f.batch_id=v_b AND f.vej=v_vej AND f.kan_nu AND f.niveau IS NULL)
        AND pg_temp.preview_q3(purge_test.id('P'),v_b,v_vej,NULL),'preview_q3_fremmed_historik_ingen_post');
    END LOOP;
    PERFORM pg_temp.preview_reverse_ok(v_b,false);
    -- Fjern planens konkrete historikafhængigheder og narrativ; append-only kræver det rigtige manifest.
    INSERT INTO private.person_purge_manifest(xid,backend_pid,person_id,tabel,pk,grund)
      SELECT pg_current_xact_id(),pg_backend_pid(),purge_test.id('P'),p->>'tabel',p->'pk',p->>'grund'
      FROM jsonb_array_elements(v_plan) p WHERE p->>'tabel'='private.narrative_publication_event'
        AND p->'pk'=jsonb_build_object('id',v_event) AND p->>'handling'='slet';
    DELETE FROM private.narrative_publication_event WHERE id=v_event;
    DELETE FROM private.narrative_record_publication WHERE id=v_binding;
    DELETE FROM public.narrative WHERE id=v_n;
    v_after:=private.narrative_record_state(v_q,(j->>'source_id')::bigint,j#>>'{person_payload,source_record_key}',false);
    PERFORM pg_temp.preview_assert(v_before=v_after AND v_after->>'state_sha256'=v_receipt->>'state_sha256',
      'preview_q3_fremmed_historik_fjernet_state');
    PERFORM pg_temp.preview_reverse_ok(v_b,false);
    RAISE SQLSTATE 'ZX001';
  EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL; END;
END $unrelated_history$;
\echo OK preview_q3_fremmed_historik_ingen_post_rpc_virker

DO $publication$
DECLARE v_b uuid:=purge_test.u('c_batch'); v_a uuid; v_new uuid; v_e jsonb; v_p_event bigint; j jsonb; v_case int; v_error text;
BEGIN
  -- Grundfixturen: P og tredje. Kun P's event fjernes; tredjes state/version bevares => NOTE.
  PERFORM pg_temp.preview_assert(pg_temp.preview_q3(purge_test.id('P'),v_b,'red_reverse_reimport_publication','note'),
    'preview_publication_eget_deltab_note');
  BEGIN
    SELECT id INTO STRICT v_p_event FROM private.reimport_event WHERE batch_id=v_b AND canonical_person_id=purge_test.id('P');
    INSERT INTO private.person_purge_manifest(xid,backend_pid,person_id,tabel,pk,grund)
      VALUES(pg_current_xact_id(),pg_backend_pid(),purge_test.id('P'),'private.reimport_event',jsonb_build_object('id',v_p_event),'egen');
    DELETE FROM private.reimport_event WHERE id=v_p_event;
    PERFORM pg_temp.preview_reverse_ok(v_b,true,1); -- Virker stadig for tredje efter eget deltab.
    RAISE SQLSTATE 'ZX001';
  EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL; END;
  FOR v_case IN 1..2 LOOP
    BEGIN
      v_new:=gen_random_uuid(); v_a:=gen_random_uuid();
      PERFORM pg_temp.preview_clone('private.reimport_authorization',format('id=(SELECT authorization_id FROM private.reimport_batch WHERE id=%L)',v_b),
        jsonb_build_object('id',v_a,'nonce',gen_random_uuid()));
      PERFORM pg_temp.preview_clone('private.reimport_batch',format('id=%L',v_b),jsonb_build_object('id',v_new,'authorization_id',v_a,
        'preview_sha256',encode(extensions.digest(v_new::text,'sha256'),'hex')));
      FOR v_e IN SELECT to_jsonb(e) FROM private.reimport_event e WHERE batch_id=v_b
        AND (v_case=2 OR canonical_person_id=purge_test.id('P')) LOOP
        -- Case 1: kun P/X1 => NOTE. Case 2: X1's event BEVARES (canonical=tredje), og T1 er også i batchen.
        PERFORM pg_temp.preview_clone('private.reimport_event',format('id=%s',v_e->>'id'),
          jsonb_build_object('id',nextval(pg_get_serial_sequence('private.reimport_event','id')),'batch_id',v_new,
            'canonical_person_id',CASE WHEN v_case=2 THEN purge_test.id('tredje') ELSE purge_test.id('P') END));
      END LOOP;
      PERFORM pg_temp.preview_reverse_ok(v_new,true,CASE WHEN v_case=1 THEN 1 ELSE 2 END);
      PERFORM pg_temp.preview_assert(pg_temp.preview_q3(purge_test.id('P'),v_new,'red_reverse_reimport_publication',
        CASE WHEN v_case=1 THEN 'note' ELSE 'advarsel' END),'preview_publication_niveau');
      IF v_case=2 THEN
        -- En rigtig ny state-version på X1 beviser, at en bevaret event med drift bryder hele RPC'en.
        PERFORM public.red_afgoer_source_persona(purge_test.u('X1'),1,'different',NULL,'Fixture');
        SET LOCAL ROLE service_role;
        v_a:=public.red_authorize_reimport_reversal(v_new,gen_random_uuid(),now()+interval '10 minutes');
        RESET ROLE;
        BEGIN
          SET LOCAL ROLE authenticated; PERFORM public.red_reverse_reimport_publication(v_new,v_a); RESET ROLE;
          RAISE EXCEPTION 'TEST_FAILED preview_publication_drift_rpc';
        EXCEPTION WHEN raise_exception THEN GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT;
          IF v_error IS DISTINCT FROM 'PUBLICATION_REVERSAL_VERSION_DRIFT' THEN RAISE; END IF;
        END;
      END IF;
      RAISE SQLSTATE 'ZX001';
    EXCEPTION WHEN SQLSTATE 'ZX001' THEN NULL; END;
  END LOOP;
END $publication$;
\echo OK preview_publication_eget_deltab_note_rpc_virker
\echo OK preview_publication_p_only_note
\echo OK preview_publication_bevaret_drift_advarsel
ROLLBACK;
\endif

-- =====================================================================================================================
-- Task 8a: vagterne testes uden red_slet_person_helt (Task 8b). Hvert scenarie rulles tilbage i egen transaktion.
\if :g_vagt
CREATE FUNCTION pg_temp.vagt_afvis(p_sql text,p_kode text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_afvist boolean:=false;
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM NOT LIKE p_kode||':%' AND SQLERRM<>p_kode THEN RAISE; END IF;
    v_afvist:=true;
  END;
  IF NOT v_afvist THEN RAISE EXCEPTION 'TEST_FAILED vagt: forventede %',p_kode; END IF;
END $$;
-- Kaldes også under SET ROLE authenticated (red_upsert_fakta); basens default privileges giver ikke PUBLIC EXECUTE.
GRANT EXECUTE ON FUNCTION pg_temp.vagt_afvis(text,text) TO authenticated;

-- Kataloget skal fastholde navnorden for vagter, der kan låse forskellige mål på samme række.
BEGIN;
DO $t$
DECLARE r record; v_poly int; v_maal int;
BEGIN
  FOR r IN SELECT * FROM (VALUES
    ('assertion',1,1),('note',1,1),('conclusion',0,1),('relation',1,0),('fact',1,0)
  ) x(tabel,polymorf,maal) LOOP
    SELECT count(*) FILTER (WHERE tgfoid='private.validate_polymorf_subjekt_findes()'::regprocedure),
           count(*) FILTER (WHERE tgfoid='public.enforce_relation_evidence_target()'::regprocedure)
      INTO v_poly,v_maal FROM pg_trigger
     WHERE tgrelid=to_regclass('public.'||r.tabel) AND tgtype=23
       AND tgenabled IN ('O','A') AND NOT tgisinternal;
    IF (v_poly,v_maal) IS DISTINCT FROM (r.polymorf,r.maal) THEN
      RAISE EXCEPTION 'TEST_FAILED vagt_triggerorden: manglende/duplikeret vagt på %',r.tabel;
    END IF;
  END LOOP;
  -- Assertion har uafhængigt objekt og mål. Note har ét mål; conclusion kun målvagten.
  -- Relation sorterer begge ender i én vagt; fact's anden vagt kører kun ved DELETE.
  IF EXISTS (
    SELECT 1 FROM pg_trigger p JOIN pg_trigger m ON m.tgrelid=p.tgrelid
     WHERE p.tgrelid='public.assertion'::regclass
       AND p.tgfoid='private.validate_polymorf_subjekt_findes()'::regprocedure
       AND m.tgfoid='public.enforce_relation_evidence_target()'::regprocedure
       AND p.tgname::text COLLATE "C" >= m.tgname::text COLLATE "C"
  ) THEN RAISE EXCEPTION 'TEST_FAILED vagt_triggerorden: person/familie skal låses før fakta/relation'; END IF;
END $t$;
ROLLBACK;
\echo OK vagt_triggerorden

BEGIN;
DO $t$
DECLARE v_p bigint; v_fam bigint; v_fact bigint; v_narr bigint; r record; v_typ text;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','a2a00000-0000-4000-8000-00000000a001',true);
  PERFORM purge_test.nyt();
  INSERT INTO public.person(levende,privat) VALUES (false,false) RETURNING id INTO v_p;
  INSERT INTO public.family(type) VALUES ('test') RETURNING id INTO v_fam;
  INSERT INTO public.fact(subjekt_type,subjekt_id,faktatype) VALUES ('person',v_p,'test') RETURNING id INTO v_fact;
  DELETE FROM public.fact WHERE id=v_fact;
  DELETE FROM public.person WHERE id=v_p;
  DELETE FROM public.family WHERE id=v_fam;
  SELECT min(id) INTO v_narr FROM public.narrative;
  IF v_narr IS NULL THEN RAISE EXCEPTION 'TEST_FAILED eksistensvagt: mangler narrativ'; END IF;
  FOR r IN SELECT * FROM (VALUES ('person',v_p),('family',v_fam),('Person',v_p),('Family',v_fam)) x(typ,id) LOOP
    -- RPC kaldes som klient; de direkte DML-prober kontrollerer også skriverløse steder.
    SET LOCAL ROLE authenticated;
    PERFORM pg_temp.vagt_afvis(format('SELECT public.red_upsert_fakta(%L,%s,%L,%L)',r.typ,r.id,'test','test'),
                              'POLYMORF_SUBJEKT_FINDES_IKKE');
    RESET ROLE;
    PERFORM pg_temp.vagt_afvis(format('INSERT INTO public.note(target_type,target_id) VALUES (%L,%s)',r.typ,r.id),'POLYMORF_SUBJEKT_FINDES_IKKE');
    PERFORM pg_temp.vagt_afvis(format('INSERT INTO public.story(subjekt_type,subjekt_id,tekst) VALUES (%L,%s,%L)',r.typ,r.id,'test'),'POLYMORF_SUBJEKT_FINDES_IKKE');
    PERFORM pg_temp.vagt_afvis(format('INSERT INTO public.suggestion(subjekt_type,subjekt_id) VALUES (%L,%s)',r.typ,r.id),'POLYMORF_SUBJEKT_FINDES_IKKE');
    PERFORM pg_temp.vagt_afvis(format('INSERT INTO public.narrative(subjekt_type,subjekt_id,tekst) VALUES (%L,%s,%L)',r.typ,r.id,'test'),'POLYMORF_SUBJEKT_FINDES_IKKE');
    PERFORM pg_temp.vagt_afvis(format('INSERT INTO public.haendelse(subjekt_type,subjekt_id,narrative_id,noegle,klausul) VALUES (%L,%s,%s,%L,%L)',r.typ,r.id,v_narr,'vagt','test'),'POLYMORF_SUBJEKT_FINDES_IKKE');
    PERFORM pg_temp.vagt_afvis(format('INSERT INTO public.assertion(target_type,target_id,objekt_type,objekt_id) VALUES (%L,%s,%L,%s)',
      'fact',purge_test.id('fakta_titel'),r.typ,r.id),'POLYMORF_SUBJEKT_FINDES_IKKE');
    PERFORM pg_temp.vagt_afvis(format('INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES (%L,%s,%L,%s,%L)',
      r.typ,r.id,'person',purge_test.id('nabo'),'test'),'POLYMORF_SUBJEKT_FINDES_IKKE');
    PERFORM pg_temp.vagt_afvis(format('INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES (%L,%s,%L,%s,%L)',
      'person',purge_test.id('nabo'),r.typ,r.id,'test'),'POLYMORF_SUBJEKT_FINDES_IKKE');
  END LOOP;
  FOREACH v_typ IN ARRAY ARRAY['assertion','conclusion','note'] LOOP
    PERFORM pg_temp.vagt_afvis(format('INSERT INTO public.%I(target_type,target_id) VALUES (%L,%s)',v_typ,'fact',v_fact),'POLYMORF_SUBJEKT_FINDES_IKKE');
  END LOOP;
  -- Begge relationsender af typen fact; ikke-kanonisk case testes særskilt nedenfor.
  PERFORM pg_temp.vagt_afvis(format('INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES (%L,%s,%L,%s,%L)',
    'fact',v_fact,'person',purge_test.id('nabo'),'test'),'POLYMORF_SUBJEKT_FINDES_IKKE');
  PERFORM pg_temp.vagt_afvis(format('INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES (%L,%s,%L,%s,%L)',
    'person',purge_test.id('nabo'),'fact',v_fact,'test'),'POLYMORF_SUBJEKT_FINDES_IKKE');
END $t$;
ROLLBACK;
\echo OK eksistensvagt

BEGIN;
DO $t$
DECLARE v_f bigint; v_r bigint; v_id bigint; v_target bigint; v_typ text; v_tabel text; v_ende text;
BEGIN
  PERFORM purge_test.nyt();
  INSERT INTO public.fact(subjekt_type,subjekt_id,faktatype)
    VALUES ('person',purge_test.id('nabo'),'test') RETURNING id INTO v_f;
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('person',purge_test.id('nabo'),'person',purge_test.id('tredje'),'test') RETURNING id INTO v_r;
  FOREACH v_typ IN ARRAY ARRAY['fact','relation'] LOOP
    v_target:=CASE WHEN v_typ='fact' THEN v_f ELSE v_r END;
    FOREACH v_tabel IN ARRAY ARRAY['note','assertion','conclusion'] LOOP
      -- Gyldigt mål findes: det er typen, ikke eksistensen, der skal give afvisningen.
      PERFORM pg_temp.vagt_afvis(format('INSERT INTO public.%I(target_type,target_id) VALUES (%L,%s)',
        v_tabel,initcap(v_typ),v_target),'POLYMORF_TYPE_IKKE_KANONISK');
      EXECUTE format('INSERT INTO public.%I(target_type,target_id) VALUES (%L,%s) RETURNING id',
        v_tabel,v_typ,v_target) INTO v_id;
      PERFORM pg_temp.vagt_afvis(format('UPDATE public.%I SET target_type=%L WHERE id=%s',
        v_tabel,initcap(v_typ),v_id),'POLYMORF_TYPE_IKKE_KANONISK');
    END LOOP;
  END LOOP;
  FOREACH v_ende IN ARRAY ARRAY['subjekt','objekt'] LOOP
    IF v_ende='subjekt' THEN
      PERFORM pg_temp.vagt_afvis(format('INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES (%L,%s,%L,%s,%L)',
        'Fact',v_f,'person',purge_test.id('nabo'),'test'),'POLYMORF_TYPE_IKKE_KANONISK');
      INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
        VALUES ('fact',v_f,'person',purge_test.id('nabo'),'test') RETURNING id INTO v_id;
    ELSE
      PERFORM pg_temp.vagt_afvis(format('INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES (%L,%s,%L,%s,%L)',
        'person',purge_test.id('nabo'),'Fact',v_f,'test'),'POLYMORF_TYPE_IKKE_KANONISK');
      INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
        VALUES ('person',purge_test.id('nabo'),'fact',v_f,'test') RETURNING id INTO v_id;
    END IF;
    PERFORM pg_temp.vagt_afvis(format('UPDATE public.relation SET %I=%L WHERE id=%s',
      v_ende||'_type','Fact',v_id),'POLYMORF_TYPE_IKKE_KANONISK');
  END LOOP;
END $t$;
ROLLBACK;
\echo OK vagt_type_kanonisk

-- Begge media-ender: eksistens, kanonisk type, INSERT/UPDATE og en faktisk tuple-lås.
BEGIN;
DO $t$
DECLARE v_end text; v_id bigint; v_m bigint:=purge_test.id('medie_delt'); v_body text;
BEGIN
  PERFORM purge_test.nyt();
  SELECT prosrc INTO v_body FROM pg_proc WHERE oid='private.validate_polymorf_subjekt_findes()'::regprocedure;
  IF position('FROM public.media WHERE id=r.id FOR KEY SHARE' IN v_body)=0 THEN
    RAISE EXCEPTION 'TEST_FAILED vagt_media_key_share';
  END IF;
  FOREACH v_end IN ARRAY ARRAY['subjekt','objekt'] LOOP
    IF v_end='subjekt' THEN
      PERFORM pg_temp.vagt_afvis(format('INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES (''media'',9223372036854775807,''person'',%s,''test'')',
        purge_test.id('nabo')),'POLYMORF_SUBJEKT_FINDES_IKKE');
      PERFORM pg_temp.vagt_afvis(format('INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES (''Media'',%s,''person'',%s,''test'')',
        v_m,purge_test.id('nabo')),'POLYMORF_TYPE_IKKE_KANONISK');
      INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
        VALUES('media',v_m,'person',purge_test.id('nabo'),'test') RETURNING id INTO v_id;
    ELSE
      PERFORM pg_temp.vagt_afvis(format('INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES (''person'',%s,''media'',9223372036854775807,''test'')',
        purge_test.id('nabo')),'POLYMORF_SUBJEKT_FINDES_IKKE');
      PERFORM pg_temp.vagt_afvis(format('INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle) VALUES (''person'',%s,''Media'',%s,''test'')',
        purge_test.id('nabo'),v_m),'POLYMORF_TYPE_IKKE_KANONISK');
      INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
        VALUES('person',purge_test.id('nabo'),'media',v_m,'test') RETURNING id INTO v_id;
    END IF;
    IF NOT EXISTS(SELECT 1 FROM public.media WHERE id=v_m AND xmax::text=pg_current_xact_id()::text) THEN
      RAISE EXCEPTION 'TEST_FAILED vagt_media_key_share';
    END IF;
    PERFORM pg_temp.vagt_afvis(format('UPDATE public.relation SET %I=''Media'' WHERE id=%s',v_end||'_type',v_id),'POLYMORF_TYPE_IKKE_KANONISK');
    PERFORM pg_temp.vagt_afvis(format('UPDATE public.relation SET %I=9223372036854775807 WHERE id=%s',v_end||'_id',v_id),'POLYMORF_SUBJEKT_FINDES_IKKE');
    DELETE FROM public.relation WHERE id=v_id;
  END LOOP;
END $t$;
ROLLBACK;
\echo OK vagt_media_ende_afvises_og_laases

BEGIN;
DO $t$
DECLARE v_f bigint; v_a bigint; v_id bigint; v_end text;
BEGIN
  PERFORM purge_test.nyt();
  INSERT INTO public.fact(subjekt_type,subjekt_id,faktatype) VALUES ('person',purge_test.id('nabo'),'test') RETURNING id INTO v_f;
  INSERT INTO public.assertion(target_type,target_id,uforanderlig) VALUES ('fact',v_f,false) RETURNING id INTO v_a;
  PERFORM pg_temp.vagt_afvis(format('DELETE FROM public.fact WHERE id=%s',v_f),'FACT_HAR_EVIDENS');
  DELETE FROM public.assertion WHERE id=v_a;
  -- De øvrige tre FK-løse veje beskytter samme forælderhalvdel.
  INSERT INTO public.conclusion(target_type,target_id) VALUES ('fact',v_f) RETURNING id INTO v_id;
  PERFORM pg_temp.vagt_afvis(format('DELETE FROM public.fact WHERE id=%s',v_f),'FACT_HAR_EVIDENS');
  DELETE FROM public.conclusion WHERE id=v_id;
  INSERT INTO public.note(target_type,target_id) VALUES ('fact',v_f) RETURNING id INTO v_id;
  PERFORM pg_temp.vagt_afvis(format('DELETE FROM public.fact WHERE id=%s',v_f),'FACT_HAR_EVIDENS');
  DELETE FROM public.note WHERE id=v_id;
  FOREACH v_end IN ARRAY ARRAY['subjekt','objekt'] LOOP
    IF v_end='subjekt' THEN
      INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
        VALUES ('fact',v_f,'person',purge_test.id('nabo'),'test') RETURNING id INTO v_id;
    ELSE
      INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
        VALUES ('person',purge_test.id('nabo'),'fact',v_f,'test') RETURNING id INTO v_id;
    END IF;
    PERFORM pg_temp.vagt_afvis(format('DELETE FROM public.fact WHERE id=%s',v_f),'FACT_HAR_EVIDENS');
    DELETE FROM public.relation WHERE id=v_id;
  END LOOP;
  DELETE FROM public.fact WHERE id=v_f;
  IF EXISTS (SELECT 1 FROM public.fact WHERE id=v_f) THEN RAISE EXCEPTION 'TEST_FAILED fakta_slettevagt'; END IF;
END $t$;
ROLLBACK;
\echo OK fakta_slettevagt

BEGIN;
DO $t$
DECLARE v_p bigint; v_n bigint; v_r bigint; v_count int;
BEGIN
  PERFORM purge_test.nyt();
  INSERT INTO public.person(levende,privat) VALUES (false,false) RETURNING id INTO v_p;
  INSERT INTO public.note(target_type,target_id,indhold) VALUES ('Person',v_p,'test') RETURNING id INTO v_n;
  INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
    VALUES ('Person',v_p,'person',purge_test.id('nabo'),'test') RETURNING id INTO v_r;
  -- Forælderhalvdelen for person/familie er bevidst uden for scope; sådan laves historiske forældreløse rækker.
  DELETE FROM public.person WHERE id=v_p;
  UPDATE public.note SET target_type=target_type,target_id=target_id,indhold='ændret' WHERE id=v_n;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count<>1 THEN RAISE EXCEPTION 'TEST_FAILED vagt_update_uaendret: note'; END IF;
  UPDATE public.relation SET subjekt_type=subjekt_type,subjekt_id=subjekt_id,objekt_type=objekt_type,objekt_id=objekt_id,
    rolle='test-ændret' WHERE id=v_r;
  GET DIAGNOSTICS v_count=ROW_COUNT;
  IF v_count<>1 THEN RAISE EXCEPTION 'TEST_FAILED vagt_update_uaendret: relation'; END IF;
  PERFORM pg_temp.vagt_afvis(format('UPDATE public.note SET target_id=%s WHERE id=%s',v_p+10000000,v_n),'POLYMORF_SUBJEKT_FINDES_IKKE');
END $t$;
ROLLBACK;
\echo OK vagt_update_uaendret

BEGIN;
DO $t$
DECLARE v_p bigint; v_f bigint; v_s bigint; v_h bigint; v_n bigint; v_key text;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','a2a00000-0000-4000-8000-00000000a001',true);
  PERFORM purge_test.nyt();
  INSERT INTO public.person(levende,privat) VALUES (false,false) RETURNING id INTO v_p;
  INSERT INTO public.family(type) VALUES ('test') RETURNING id INTO v_f;
  INSERT INTO public.story(subjekt_type,subjekt_id,tekst) VALUES ('person',v_p,'test') RETURNING id INTO v_s;
  INSERT INTO public.narrative(subjekt_type,subjekt_id,tekst) VALUES ('person',v_p,'test') RETURNING id INTO v_n;
  INSERT INTO public.haendelse(subjekt_type,subjekt_id,narrative_id,noegle,klausul)
    VALUES ('person',v_p,v_n,'vagt','test') RETURNING id INTO v_h;
  SET LOCAL ROLE authenticated;
  PERFORM public.red_set_feed_pin('story:'||v_s,'pin');
  PERFORM public.red_set_feed_pin('arkiv:'||v_h,'pin');
  PERFORM public.red_set_feed_pin('paadennedag:h:'||v_h,'pin');
  PERFORM public.red_set_feed_pin('portrait:'||v_p,'pin');
  PERFORM public.red_set_feed_pin('portrait:'||v_p,'skjul'); -- ON CONFLICT-vejen
  PERFORM public.red_set_feed_pin('forbundet:'||v_f,'pin');
  RESET ROLE;
  DELETE FROM public.person WHERE id=v_p;
  DELETE FROM public.family WHERE id=v_f;
  FOREACH v_key IN ARRAY ARRAY['portrait:'||v_p,'citat:'||v_p,'naevnt:'||v_p,'dagensperson:'||v_p,
    'jubilaeum:'||v_p||':100','embede:'||v_p||':test:1900','paadennedag:'||v_p||':født:1900',
    'slaegt:'||v_p||':'||purge_test.id('nabo'),'slaegt:'||purge_test.id('nabo')||':'||v_p,'forbundet:'||v_f,
    'story:'||v_s,'arkiv:'||v_h,'paadennedag:h:'||v_h] LOOP
    SET LOCAL ROLE authenticated;
    PERFORM pg_temp.vagt_afvis(format('SELECT public.red_set_feed_pin(%L,%L)',v_key,'pin'),'POLYMORF_SUBJEKT_FINDES_IKKE');
    RESET ROLE;
  END LOOP;
  RESET ROLE;
END $t$;
ROLLBACK;
\echo OK feed_pin_laaser_maal

-- R6: testdata via begge rigtige pin-skrivere; fortryd skal prelocke målet før pin-rækken.
CREATE FUNCTION pg_temp.vagt_pin_slettesaet(p_typ text)
RETURNS TABLE(maal_id bigint,saet_id bigint,noegle text) LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub','a2a00000-0000-4000-8000-00000000a001',true);
  PERFORM purge_test.nyt();
  IF p_typ='person' THEN
    INSERT INTO public.person(levende,privat) VALUES (false,false) RETURNING id INTO maal_id;
    noegle:='portrait:'||maal_id;
  ELSE
    INSERT INTO public.family(type) VALUES ('test') RETURNING id INTO maal_id;
    noegle:='forbundet:'||maal_id;
  END IF;
  SET LOCAL ROLE authenticated;
  PERFORM public.red_set_feed_pin(noegle,'pin');
  RESET ROLE;
  PERFORM purge_test.nyt();
  SET LOCAL ROLE authenticated;
  PERFORM public.red_fjern_feed_pin(noegle);
  RESET ROLE;
  saet_id:=current_setting('app.change_set_id')::bigint;
  PERFORM purge_test.nyt();
  RETURN NEXT;
END $$;

BEGIN;
DO $t$
DECLARE r record; v_typ text; v_force boolean;
BEGIN
  FOREACH v_typ IN ARRAY ARRAY['person','family'] LOOP
    SELECT * INTO STRICT r FROM pg_temp.vagt_pin_slettesaet(v_typ);
    IF v_typ='person' THEN DELETE FROM public.person WHERE id=r.maal_id;
    ELSE DELETE FROM public.family WHERE id=r.maal_id;
    END IF;
    FOREACH v_force IN ARRAY ARRAY[false,true] LOOP
      SET LOCAL ROLE authenticated;
      PERFORM pg_temp.vagt_afvis(format('SELECT public.red_fortryd_change_set(%s,%L)',r.saet_id,v_force),
        format('POLYMORF_SUBJEKT_FINDES_IKKE: %s %s',v_typ,r.maal_id));
      RESET ROLE;
      IF EXISTS (SELECT 1 FROM public.feed_pin WHERE kort_noegle=r.noegle)
         OR EXISTS (SELECT 1 FROM public.change_set WHERE reverterer_id=r.saet_id) THEN
        RAISE EXCEPTION 'TEST_FAILED feed_pin_fortryd_doedt_maal: pin eller reversal blev efterladt';
      END IF;
    END LOOP;
  END LOOP;
END $t$;
ROLLBACK;
\echo OK feed_pin_fortryd_doedt_maal

BEGIN;
DO $t$
DECLARE r record; v_typ text; v_force boolean;
BEGIN
  FOREACH v_typ IN ARRAY ARRAY['person','family'] LOOP
    FOREACH v_force IN ARRAY ARRAY[false,true] LOOP
      SELECT * INTO STRICT r FROM pg_temp.vagt_pin_slettesaet(v_typ);
      SET LOCAL ROLE authenticated;
      PERFORM public.red_fortryd_change_set(r.saet_id,v_force);
      RESET ROLE;
      IF NOT EXISTS (SELECT 1 FROM public.feed_pin WHERE kort_noegle=r.noegle AND handling='pin') THEN
        RAISE EXCEPTION 'TEST_FAILED feed_pin_fortryd_levende_maal: pin blev ikke genskabt';
      END IF;
    END LOOP;
  END LOOP;
END $t$;
ROLLBACK;
\echo OK feed_pin_fortryd_levende_maal

-- Step 4b: den eksisterende sletter logger børn før forælder; generisk inverse bruger seq DESC.
BEGIN;
DO $t$
DECLARE v_p bigint; v_f bigint; v_n bigint; v_cs bigint; v_person_seq int; v_child_seq int; j jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','a2a00000-0000-4000-8000-00000000a001',true);
  PERFORM purge_test.nyt();
  INSERT INTO public.person(levende,privat) VALUES (false,false) RETURNING id INTO v_p;
  SET LOCAL ROLE authenticated;
  j:=public.red_upsert_fakta('person',v_p,'test','test');
  RESET ROLE;
  v_f:=(j->>'fact_id')::bigint;
  INSERT INTO public.note(target_type,target_id,indhold) VALUES ('person',v_p,'test') RETURNING id INTO v_n;
  PERFORM purge_test.nyt();
  SET LOCAL ROLE authenticated;
  PERFORM public.red_slet_person(v_p);
  RESET ROLE;
  v_cs:=current_setting('app.change_set_id')::bigint;
  SELECT seq INTO STRICT v_person_seq FROM public.change_event
    WHERE change_set_id=v_cs AND tabel='person' AND op='DELETE' AND row_pk=jsonb_build_object('id',v_p);
  SELECT max(seq) INTO v_child_seq FROM public.change_event
    WHERE change_set_id=v_cs AND tabel IN ('fact','note') AND op='DELETE';
  IF v_child_seq IS NULL OR v_child_seq>=v_person_seq THEN
    RAISE EXCEPTION 'TEST_FAILED vagt_fortryd_slet_person: børn slettet efter forælder';
  END IF;
  SET LOCAL ROLE authenticated;
  PERFORM public.red_fortryd_change_set(v_cs,false);
  RESET ROLE;
  IF NOT EXISTS (SELECT 1 FROM public.person WHERE id=v_p)
     OR NOT EXISTS (SELECT 1 FROM public.fact WHERE id=v_f AND subjekt_id=v_p)
     OR NOT EXISTS (SELECT 1 FROM public.note WHERE id=v_n AND target_id=v_p) THEN
    RAISE EXCEPTION 'TEST_FAILED vagt_fortryd_slet_person: restore';
  END IF;
END $t$;
ROLLBACK;
\echo OK vagt_fortryd_slet_person

-- Gammel sletter: Q → F og F → Q skal med, selv om P ikke er direkte relationsende.
BEGIN;
DO $t$
DECLARE v_p bigint; v_q bigint; v_f bigint; v_r bigint; v_a bigint; v_ende text;
        v_rels bigint[]:='{}'; v_assertions bigint[]:='{}';
BEGIN
  PERFORM set_config('request.jwt.claim.sub','a2a00000-0000-4000-8000-00000000a001',true);
  PERFORM purge_test.nyt();
  INSERT INTO public.person(levende,privat) VALUES (false,false) RETURNING id INTO v_p;
  INSERT INTO public.person(levende,privat) VALUES (false,false) RETURNING id INTO v_q;
  INSERT INTO public.fact(subjekt_type,subjekt_id,faktatype) VALUES ('person',v_p,'test') RETURNING id INTO v_f;
  FOREACH v_ende IN ARRAY ARRAY['subjekt','objekt'] LOOP
    IF v_ende='subjekt' THEN
      INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
        VALUES ('fact',v_f,'person',v_q,'test') RETURNING id INTO v_r;
    ELSE
      INSERT INTO public.relation(subjekt_type,subjekt_id,objekt_type,objekt_id,rolle)
        VALUES ('person',v_q,'fact',v_f,'test') RETURNING id INTO v_r;
    END IF;
    v_rels:=array_append(v_rels,v_r);
    INSERT INTO public.assertion(target_type,target_id,uforanderlig)
      VALUES ('relation',v_r,false) RETURNING id INTO v_a;
    v_assertions:=array_append(v_assertions,v_a);
    INSERT INTO public.citation(assertion_id) VALUES (v_a);
    INSERT INTO public.conclusion(target_type,target_id,valgt_assertion_id) VALUES ('relation',v_r,v_a);
    INSERT INTO public.note(target_type,target_id,indhold) VALUES ('relation',v_r,'test');
  END LOOP;
  PERFORM purge_test.nyt();
  SET LOCAL ROLE authenticated;
  PERFORM public.red_slet_person(v_p);
  RESET ROLE;
  IF EXISTS (SELECT 1 FROM public.person WHERE id=v_p)
     OR EXISTS (SELECT 1 FROM public.fact WHERE id=v_f)
     OR EXISTS (SELECT 1 FROM public.relation WHERE id=ANY(v_rels))
     OR EXISTS (SELECT 1 FROM public.assertion WHERE id=ANY(v_assertions))
     OR EXISTS (SELECT 1 FROM public.citation WHERE assertion_id=ANY(v_assertions))
     OR EXISTS (SELECT 1 FROM public.conclusion WHERE target_type='relation' AND target_id=ANY(v_rels))
     OR EXISTS (SELECT 1 FROM public.note WHERE target_type='relation' AND target_id=ANY(v_rels))
     OR NOT EXISTS (SELECT 1 FROM public.person WHERE id=v_q) THEN
    RAISE EXCEPTION 'TEST_FAILED vagt_gammel_sletter_fakta_ende: rest eller anden person slettet';
  END IF;
END $t$;
ROLLBACK;
\echo OK vagt_gammel_sletter_fakta_ende

-- Literal sted→beskyttelse. Kataloget afgør FK-dækningen pr. inventarkolonne; en FK på en anden kolonne
-- (fx conclusion.valgt_assertion_id) må ikke skjule et FK-løst target_id. Ikke alle inventarkolonner er
-- referencer: rødder, egne felter og fritekst har derfor en udtrykkelig accepteret-begrundelse.
BEGIN;
CREATE TEMP TABLE vagt_beskyttelse(sted text,tabel text,beskyttelse text,PRIMARY KEY(sted,tabel));
INSERT INTO vagt_beskyttelse VALUES
 ('S1','person','accepteret:selve roden; person-id er PK og genbruges ikke af skriverne'),
 ('S2','person_external_id','accepteret:person_id har FK; øvrige felter beskriver ekstern nøgle'),
 ('S3','family_member','accepteret:begge entiteter har FK'),
 ('S4','slaegtsnavn_karantaene','accepteret:person_id har FK'),
 ('S5','profiles','accepteret:personbinding har FK; brugerdata er R15'),
 ('S6','bookmark','accepteret:person_id har FK'),
 ('S7','person_slaegt_membership','accepteret:person_id har FK'),
 ('S8','person_lineage_membership','accepteret:person_id har FK'),
 ('S9','private.person_create_receipt','accepteret:R14; forbruges atomisk ved oprettelse'),
 ('S10','private.source_persona_identity','laas:L5'),
 ('S11a','private.source_persona_identity_event','laas:L5'),
 ('S11b','private.source_persona_identity_event','laas:L5'),
 ('S12','private.source_persona_identity_candidate','laas:L5'),
 ('S13','fact','vagt:private.validate_polymorf_subjekt_findes'),
 ('S13b','fact','vagt:private.validate_polymorf_subjekt_findes'),
 ('S14','relation','vagt:private.validate_polymorf_subjekt_findes'),
 ('S14b','relation','vagt:private.validate_polymorf_subjekt_findes'),
 ('S15','assertion','vagt:public.enforce_relation_evidence_target'),
 ('S16','conclusion','vagt:public.enforce_relation_evidence_target'),
 ('S17','citation','accepteret:assertion_id har FK'),
 ('S18','note','vagt:private.validate_polymorf_subjekt_findes'),
 ('S19','relation','vagt:private.validate_polymorf_subjekt_findes'),
 ('S21','narrative','vagt:private.validate_polymorf_subjekt_findes'),
 ('S22','private.narrative_record_publication','accepteret:narrative_id har FK; recordlåsen tages før publicering'),
 ('S23','private.narrative_publication_event','accepteret:narrative_id har FK; recordlåsen tages før publicering'),
 ('S24','private.narrative_legacy_publication','accepteret:narrative_id og latest_event_id har FK'),
 ('S25','haendelse','accepteret:narrative_id har FK'),
 ('S26','haendelse','vagt:private.validate_polymorf_subjekt_findes'),
 ('S27','haendelse','accepteret:fact_id og relation_id har FK'),
 ('S28','text_mention','accepteret:afledt i tekstens AFTER-trigger; kilde-rækken er allerede låst'),
 ('S30','story','vagt:private.validate_polymorf_subjekt_findes'),
 ('S30','story_kilde','accepteret:story_id har FK'),
 ('S31','story','accepteret:ankerkolonnerne har FK med ON DELETE SET NULL'),
 ('S32','feed_pin','accepteret:R6: red_set_feed_pin og generisk fortryd låser person/familie før pin-rækken'),
 ('NY-B','feed_pin','accepteret:R6: red_set_feed_pin og generisk fortryd låser person/familie før pin-rækken'),
 ('S33','entity_description','vagt:public.validate_entity_description_subject'),
 ('S33','private.entity_description_source','accepteret:description_id har FK ON DELETE CASCADE'),
 ('S34','suggestion','vagt:private.validate_polymorf_subjekt_findes'),
 ('S35','import_korrektion','accepteret:OCR-skriveren låser source og person_external_id før journalen'),
 ('S36','paastand_korrektion','accepteret:assertion_id har FK; foer/efter er journal for samme påstand'),
 ('S37','media','accepteret:selve mediet; Storage-sti er indholdsadresseret'),
 ('S37','media_variant','accepteret:media_id har FK; Storage-sti er indholdsadresseret'),
 ('S38','family','accepteret:selve familieroden; medlemskabsskriverne bruger lock_family_rows'),
 ('S39a','private.interpretation_promotion','laas:L4'),
 ('Prom_egen_fam','private.interpretation_promotion','laas:L4'),
 ('S40','private.legacy_placement_disposition','laas:L5'),
 ('S41a','private.reimport_event','laas:L4'),
 ('S42','private.reimport_name_completion_result','laas:L4'),
 ('S43a','private.reimport_case_event','laas:L4'),
 ('S45a','private.identity_control_parent_card','laas:L5'),
 ('M5','private.identity_control_parent_event','laas:L5'),
 ('S49a','private.relation_reopen','laas:L4'),
 ('S49b','private.text_revision_reconciliation','laas:L4'),
 ('S54','change_event','accepteret:log_change i samme transaktion som den beskyttede dataskrivning'),
 ('S52','change_set','accepteret:L8 plus eksistensvagterne; generisk fortryd serialiseres via K5 og L6b'),
 ('S53','change_set','accepteret:L8 plus eksistensvagterne; summary hører til samme skriveoperation'),
 ('S55','change_set','accepteret:reverterer_id har FK; sættene låses af K5 og L6b');
DO $t$
DECLARE v_bad text;
BEGIN
  SELECT string_agg(DISTINCT i.sted||':'||i.tabel,', ' ORDER BY i.sted||':'||i.tabel) INTO v_bad
    FROM private.person_purge_inventar() i
   WHERE i.handling IN ('slet','nulstil','loesn')
     AND EXISTS (
       SELECT 1 FROM unnest(i.kolonner) k
       JOIN pg_attribute a ON a.attrelid=to_regclass(CASE WHEN i.tabel LIKE 'private.%' THEN i.tabel ELSE 'public.'||i.tabel END)
                          AND a.attname=k AND NOT a.attisdropped
       WHERE NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.conrelid=a.attrelid AND c.contype='f' AND a.attnum=ANY(c.conkey)))
     AND NOT EXISTS (SELECT 1 FROM vagt_beskyttelse b WHERE (b.sted,b.tabel)=(i.sted,i.tabel));
  IF v_bad IS NOT NULL THEN RAISE EXCEPTION 'TEST_FAILED beskyttelse_daekker_fk_loese_steder: %',v_bad; END IF;
  SELECT string_agg(b.sted||':'||b.tabel,', ') INTO v_bad FROM vagt_beskyttelse b
   WHERE (b.beskyttelse LIKE 'vagt:%' AND NOT EXISTS (
            SELECT 1 FROM pg_trigger t WHERE t.tgrelid=to_regclass('public.'||b.tabel)
              AND t.tgfoid=to_regprocedure(substring(b.beskyttelse FROM 6)||'()')
              AND NOT t.tgisinternal AND t.tgenabled IN ('O','A')))
      OR NOT (b.beskyttelse LIKE 'vagt:%' OR b.beskyttelse IN ('laas:L4','laas:L5')
              OR b.beskyttelse ~ '^accepteret:.+');
  IF v_bad IS NOT NULL THEN RAISE EXCEPTION 'TEST_FAILED beskyttelse_daekker_fk_loese_steder: ugyldig beskyttelse %',v_bad; END IF;
END $t$;
ROLLBACK;
\echo OK beskyttelse_daekker_fk_loese_steder
-- 8a-opfølgning (security-review af fec84f6c): red_suggest må ikke afsløre, om et skjult id findes. En ikke-redaktør får
-- samme fejl for et skjult og et ikke-eksisterende person-/familiemål; redaktøren og offentlige mål er uændrede.
\ir fixtures/kalder-matrix.sql
BEGIN;
SELECT pg_temp.km_kaldere();
DO $t$
DECLARE v_skjult bigint; v_offentlig bigint; v_fam_skjult bigint; v_fam_tom bigint; v_ingen bigint; v_fam_ingen bigint;
  v_fejl text[] := '{}'; v_msg text; r record;
BEGIN
  PERFORM purge_test.nyt();
  INSERT INTO public.person(levende,privat) VALUES (false,true) RETURNING id INTO v_skjult;
  INSERT INTO public.person(levende,privat) VALUES (false,false) RETURNING id INTO v_offentlig;
  INSERT INTO public.family(type) VALUES ('test') RETURNING id INTO v_fam_skjult;
  INSERT INTO public.family_member(family_id,person_id,rolle) VALUES (v_fam_skjult,v_skjult,'partner');
  INSERT INTO public.family(type) VALUES ('test') RETURNING id INTO v_fam_tom;
  v_ingen := (SELECT max(id) FROM public.person)+1000;
  v_fam_ingen := (SELECT max(id) FROM public.family)+1000;
  PERFORM set_config('request.jwt.claim.sub','11000000-0000-0000-0000-00000000ca02',true);  -- medlem
  SET LOCAL ROLE authenticated;
  FOR r IN SELECT * FROM (VALUES ('person',v_skjult),('person',v_ingen),('family',v_fam_skjult),('family',v_fam_ingen)) x(typ,id) LOOP
    BEGIN
      PERFORM public.red_suggest('rettelse',r.typ,r.id,'navn','x');
      v_msg := 'LYKKEDES';
    EXCEPTION WHEN raise_exception THEN v_msg := SQLERRM;
    END;
    v_fejl := v_fejl || v_msg;
  END LOOP;
  -- Positive kontroller: offentlig person og eksisterende familie uden skjulte medlemmer.
  PERFORM public.red_suggest('rettelse','person',v_offentlig,'navn','x');
  PERFORM public.red_suggest('rettelse','family',v_fam_tom,'navn','x');
  RESET ROLE;
  IF array_length(v_fejl,1)<>4 OR EXISTS (SELECT 1 FROM unnest(v_fejl) f WHERE f<>'FORSLAG_SUBJEKT_UTILGAENGELIGT') THEN
    RAISE EXCEPTION 'TEST_FAILED red_suggest_intet_orakel: %', v_fejl;
  END IF;
  -- Redaktøren må stadig foreslå på et skjult mål.
  PERFORM set_config('request.jwt.claim.sub','11000000-0000-0000-0000-00000000ca03',true);
  SET LOCAL ROLE authenticated;
  PERFORM public.red_suggest('rettelse','person',v_skjult,'navn','x');
  RESET ROLE;
END $t$;
ROLLBACK;
\echo OK red_suggest_intet_orakel
\endif

\if :g_purge
\ir person-purge-execute-tests.sql
\else
\if :g_purge_ekstra
\ir person-purge-execute-tests.sql
\endif
\endif

-- Task 8b / R29: samme rigtige Q6-kæde, nu med en committet fuld sletning.
\if :g_purge_binding
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
CREATE TEMP TABLE purge_binding_count_before(personas jsonb,families jsonb);
-- Fuld tabeltilstand før/efter det afviste kald; ingen plan-/manifestafledt undtagelsesliste.
CREATE FUNCTION pg_temp.purge_binding_hash() RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r record; v_hash text; v_result jsonb:='{}';
BEGIN
  FOR r IN SELECT n.nspname,c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
    WHERE n.nspname IN ('public','private') AND c.relkind IN ('r','p') AND NOT c.relispartition LOOP
    EXECUTE format($q$SELECT encode(extensions.digest(convert_to(coalesce(
      string_agg(to_jsonb(t)::text,E'\n' ORDER BY to_jsonb(t)::text COLLATE "C"),''),'UTF8'),'sha256'),'hex')
      FROM %I.%I t$q$,r.nspname,r.relname) INTO v_hash;
    v_result:=v_result||jsonb_build_object(r.nspname||'.'||r.relname,v_hash);
  END LOOP;
  RETURN v_result;
END $$;
DO $binding_forsvinder$
DECLARE v_tredje bigint;
  v_actor uuid := 'a2a00000-0000-4000-8000-00000000a001';
  v_source bigint; v_src jsonb; v_other_source bigint; v_other_src jsonb; v_control uuid; v_m jsonb; v_items jsonb; v_preview jsonb;
  v_i uuid; v_version integer; v_hash text; v_promotion uuid; v_error text;
  v_sp_source bigint; v_sp_src jsonb; v_sp jsonb; v_sp_i uuid; v_sp_version integer; v_sp_promotion uuid; v_sp_identity_version integer;
  v_before jsonb; v_sp_hash text; v_new_family bigint; v_reopened uuid; v_sp_new_i uuid; v_sp_new_hash text;
  v_other jsonb; v_other_hash text; v_child jsonb; v_parent jsonb; v_parent_i uuid; v_parent_key uuid;
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
    WHERE id IN (v_p,purge_test.id('barn'),purge_test.id('anden_partner'));
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
  IF NOT EXISTS(SELECT 1 FROM private.interpretation WHERE id=v_i AND source_persona_id IS NULL)
     OR NOT EXISTS(SELECT 1 FROM private.interpretation_party_current
       WHERE interpretation_key=(v_m->'claim'->>'key')::uuid AND party_role='principal'
         AND source_persona_id=(v_m->'post'->>'principal')::uuid)
     OR NOT EXISTS(SELECT 1 FROM private.person_purge_plan(v_p) WHERE sted='Prom_egen_fam'
       AND handling='slet' AND pk=jsonb_build_object('id',v_promotion)) THEN
    RAISE EXCEPTION 'TEST_FAILED purge_q6_principal_party';
  END IF;
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
  -- Den omvendte post: hovedpersonen er en anden; P står KUN som spouse-part.
  -- R39: andres bundne ægteskab må ikke miste sin gældende spouse ved sletning.
  v_sp_source:=nextval(pg_get_serial_sequence('public.source','id'));
  v_sp_src:=pg_temp.f5b_source(v_sp_source);
  v_sp:=pg_temp.f2a_marriage(v_sp_source,v_sp_src,'PURGE-Q6-SPOUSE',purge_test.id('anden_partner'),v_p,v_actor,2,2,false);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  SET LOCAL ROLE authenticated;
  v_preview:=public.red_preview_relation_decisions(v_sp_source);
  IF public.red_decide_relation_interpretations(v_sp_source,v_preview->>'set_sha256') IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'TEST_FAILED purge_q6_spouse_afgoerelse';
  END IF;
  RESET ROLE;
  SELECT id,version INTO STRICT v_sp_i,v_sp_version FROM private.interpretation_current
    WHERE interpretation_key=(v_sp->'claim'->>'key')::uuid;
  SELECT version INTO STRICT v_sp_identity_version FROM private.source_persona_identity
    WHERE source_persona_id=(v_sp->>'spouse_persona')::uuid;
  v_items:=jsonb_build_array(jsonb_build_object('interpretation_id',v_sp_i::text,'family_id',v_family));
  v_preview:=private.preview_relation_promotions(v_sp_source,v_items,false);
  SET LOCAL ROLE authenticated;
  PERFORM public.red_promote_relation_interpretations_batch(v_sp_source,v_items,v_preview->>'preview_sha256');
  RESET ROLE;
  SELECT id INTO STRICT v_sp_promotion FROM private.interpretation_promotion
    WHERE interpretation_id=v_sp_i AND target_type='family';
  v_sp_hash:=private.relation_binding_state_sha256(v_sp_i);
  -- Lokalt facit: blokér skal vinde over S39c/S48 for samme fysiske række.
  IF v_sp_hash IS NULL OR (SELECT count(*) FROM private.person_purge_plan(v_p)
      WHERE tabel='private.interpretation_promotion' AND pk=jsonb_build_object('id',v_sp_promotion))<>1
     OR NOT EXISTS(SELECT 1 FROM private.person_purge_plan(v_p)
       WHERE (sted,tabel,pk,handling)=('S39f','private.interpretation_promotion',
         jsonb_build_object('id',v_sp_promotion),'blokér')) THEN
    RAISE EXCEPTION 'TEST_FAILED purge_q6_spouse_bloker_facit';
  END IF;
  PERFORM pg_temp.f2a_publish(v_sp_source,v_sp_src,v_sp->'post',purge_test.id('anden_partner'),v_actor,'Anna Alfa. Gift med Bo Beta.');
  PERFORM pg_temp.f2a_publish(v_source,v_src,v_m->'post',v_p,v_actor,'Anna Alfa. Gift med Bo Beta.');
  PERFORM pg_temp.f2a_publish(v_other_source,v_other_src,v_child,purge_test.id('barn'),v_actor,'Barn Alfa. søn af Far.');
  IF (SELECT count(*) FROM public.public_family_sources(ARRAY[v_family]))<>3 THEN
    RAISE EXCEPTION 'TEST_FAILED binding_andres_bevaret: tre offentlige kilder kræves før';
  END IF;

  PERFORM purge_test.nyt();
  v_before:=pg_temp.purge_binding_hash();
  v_preview:=public.red_slet_person_helt_preview(v_p);
  IF NOT EXISTS(SELECT 1 FROM jsonb_array_elements(v_preview->'blokeringer') b
      WHERE b=jsonb_build_object('art','anden_promotion','sted','S39f',
        'tabel','private.interpretation_promotion','pk',jsonb_build_object('id',v_sp_promotion))) THEN
    RAISE EXCEPTION 'TEST_FAILED purge_q6_spouse_preview_art_pk_uden_tekst';
  END IF;
  v_error:=NULL;
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM public.red_slet_person_helt(v_p,v_preview->>'sha256');
    RESET ROLE;
  EXCEPTION WHEN raise_exception THEN
    v_error:=SQLERRM;
  END;
  IF v_error IS DISTINCT FROM 'PURGE_BLOKERET: anden_promotion' THEN
    RAISE EXCEPTION 'TEST_FAILED purge_q6_spouse_blokeret';
  END IF;
  IF pg_temp.purge_binding_hash() IS DISTINCT FROM v_before
     OR NOT EXISTS(SELECT 1 FROM public.person WHERE id=v_p)
     OR private.relation_binding_state_sha256(v_sp_i) IS DISTINCT FROM v_sp_hash
     OR NOT EXISTS(SELECT 1 FROM private.interpretation_promotion WHERE id=v_sp_promotion
       AND evidence->>'state_sha256'=v_sp_hash)
     OR (SELECT count(*) FROM public.public_family_sources(ARRAY[v_family]))<>3 THEN
    RAISE EXCEPTION 'TEST_FAILED purge_q6_spouse_afvisning_uaendret';
  END IF;

  -- Positiv kontrol gennem rigtige skrivere: ret spouse-identiteten til tredje, genåbn,
  -- afgør og bind Q's ægteskab i Q+tredjes familie, mens P stadig findes.
  v_new_family:=pg_temp.f5b_family(purge_test.id('anden_partner'),purge_test.id('tredje'),2);
  v_tredje:=purge_test.id('tredje');  -- før rolleskiftet: authenticated har ingen adgang til purge_test
  SET LOCAL ROLE authenticated;
  PERFORM public.red_afgoer_source_persona((v_sp->>'spouse_persona')::uuid,v_sp_identity_version,
    'same',v_tredje,'R39: spouse var tredje, ikke P','{}');
  v_reopened:=public.red_genaabn_relation_interpretation(v_sp_i,v_sp_version,'R39: rettet spouse',v_context);
  v_preview:=public.red_preview_relation_decisions(v_sp_source);
  IF public.red_decide_relation_interpretations(v_sp_source,v_preview->>'set_sha256') IS DISTINCT FROM 1 THEN
    RAISE EXCEPTION 'TEST_FAILED purge_q6_spouse_rettet_afgoerelse';
  END IF;
  RESET ROLE;
  SELECT id INTO STRICT v_sp_new_i FROM private.interpretation_current
    WHERE interpretation_key=(v_sp->'claim'->>'key')::uuid AND supersedes_id=v_reopened;
  v_items:=jsonb_build_array(jsonb_build_object('interpretation_id',v_sp_new_i::text,'family_id',v_new_family));
  v_preview:=private.preview_relation_promotions(v_sp_source,v_items,false);
  SET LOCAL ROLE authenticated;
  PERFORM public.red_promote_relation_interpretations_batch(v_sp_source,v_items,v_preview->>'preview_sha256');
  RESET ROLE;
  v_sp_new_hash:=private.relation_binding_state_sha256(v_sp_new_i);
  IF v_sp_new_hash IS NULL OR EXISTS(SELECT 1 FROM private.person_purge_plan(v_p) WHERE sted='S39f')
     OR NOT EXISTS(SELECT 1 FROM private.person_purge_plan(v_p) WHERE sted='S39c'
       AND handling='bevar_andres' AND pk=jsonb_build_object('id',v_sp_promotion))
     OR EXISTS(SELECT 1 FROM jsonb_array_elements(public.red_slet_person_helt_preview(v_p)->'blokeringer') b
       WHERE b->>'sted'='S39f') THEN
    RAISE EXCEPTION 'TEST_FAILED purge_q6_spouse_rettet_blokerer_ikke';
  END IF;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;

  INSERT INTO purge_binding_count_before SELECT
    coalesce((SELECT jsonb_agg(source_persona_id) FROM private.source_persona_identity
      WHERE canonical_person_id=v_p AND decision_status='accepted'),'[]'::jsonb),
    coalesce((SELECT jsonb_agg(DISTINCT family_id) FROM public.family_member WHERE person_id=v_p),'[]'::jsonb);
  PERFORM purge_test.nyt();
  v_preview:=public.red_slet_person_helt_preview(v_p);
  SET LOCAL ROLE authenticated;
  PERFORM public.red_slet_person_helt(v_p,v_preview->>'sha256');
  RESET ROLE;
  IF EXISTS(SELECT 1 FROM private.interpretation_promotion WHERE id=v_promotion)
     OR EXISTS(SELECT 1 FROM public.person WHERE id=v_p)
     OR NOT EXISTS(SELECT 1 FROM private.interpretation_promotion WHERE interpretation_id=v_parent_i)
     OR private.relation_binding_state(v_i) IS NOT NULL
     OR private.relation_binding_state_sha256(v_i) IS NOT NULL THEN
    RAISE EXCEPTION 'TEST_FAILED purge_q6_binding_rigtig_sletning';
  END IF;
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM public.red_genaabn_relation_interpretation(v_i,v_version,'Q6: slettet',v_context);
    RESET ROLE;
    RAISE EXCEPTION 'TEST_FAILED purge_q6_genaabning';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM IS DISTINCT FROM 'RELATION_REOPEN_STATE_INVALID' THEN RAISE; END IF;
  END;
  IF private.relation_binding_state(v_parent_i) IS NULL
     OR private.relation_binding_state_sha256(v_parent_i) IS DISTINCT FROM v_other_hash
     OR NOT EXISTS(SELECT 1 FROM private.text_revision_binding_set(ARRAY[v_parent_key]))
     OR (SELECT count(*) FROM public.public_family_sources(ARRAY[v_family]))<>1 THEN
    RAISE EXCEPTION 'TEST_FAILED purge_q6_andres_binding';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM private.interpretation_promotion WHERE id=v_sp_promotion)
     OR private.relation_binding_state_sha256(v_sp_new_i) IS DISTINCT FROM v_sp_new_hash
     OR NOT EXISTS(SELECT 1 FROM private.text_revision_binding_set(ARRAY[(v_sp->'claim'->>'key')::uuid]))
     OR (SELECT count(*) FROM public.public_family_sources(ARRAY[v_new_family]))<>1 THEN
    RAISE EXCEPTION 'TEST_FAILED purge_q6_spouse_rettet_binding_bevaret';
  END IF;
  SET CONSTRAINTS ALL IMMEDIATE;
END $binding_forsvinder$;
COMMIT;
\echo OK purge_q6_binding_rigtig_sletning
\echo OK purge_q6_andres_binding
\echo OK purge_q6_spouse_bloker_facit
\echo OK purge_q6_spouse_preview_art_pk_uden_tekst
\echo OK purge_q6_spouse_blokeret
\echo OK purge_q6_spouse_afvisning_uaendret
\echo OK purge_q6_spouse_rettet_blokerer_ikke
\echo OK purge_q6_spouse_rettet_binding_bevaret
SELECT personas AS purge_count_personas,families AS purge_count_families FROM purge_binding_count_before \gset
SELECT purge_test.id('P') AS pid \gset
\set purge_assert_nul true
\o /dev/null
\ir person-purge-count.sql
\o
\echo OK purge_q6_uafhaengig_count_nul
\endif

\if :g_fortryd_link
\ir person-purge-fortryd-link-tests.sql
\endif

\if :g_db_verify
\ir person-purge-db-verify-tests.sql
\endif

-- Task 12: udbakke, kald som rigtige roller og en rigtig sletning med COMMIT.
\if :g_udbakke
CREATE FUNCTION pg_temp.udbakke_assert(p_ok boolean,p_test text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'TEST_FAILED %',p_test; END IF; END $$;
BEGIN;
\ir fixtures/kalder-matrix.sql
SELECT pg_temp.km_kaldere();
INSERT INTO private.person_purge_udbakke(bucket,sti) VALUES
  ('purge-task12-a','en'),('purge-task12-a','to'),('purge-task12-b','en');
CREATE TEMP TABLE udbakke_foer AS SELECT * FROM private.person_purge_udbakke;
DO $t$
DECLARE k text; q text; v_error text; v_state text; sig text;
BEGIN
  FOREACH sig IN ARRAY ARRAY['public.red_person_purge_udbakke()','public.red_person_purge_udbakke_kvitter(text,text)'] LOOP
    PERFORM pg_temp.udbakke_assert(has_function_privilege('authenticated',sig,'EXECUTE')
      AND NOT has_function_privilege('anon',sig,'EXECUTE') AND NOT has_function_privilege('service_role',sig,'EXECUTE'),'udbakke_acl');
    PERFORM pg_temp.udbakke_assert(EXISTS (SELECT 1 FROM pg_proc WHERE oid=to_regprocedure(sig)
      AND prosecdef AND proconfig @> ARRAY['search_path=pg_catalog, public, private']), 'udbakke_definer_search_path');
  END LOOP;
  FOREACH k IN ARRAY ARRAY['gaest','uden_profil','medlem'] LOOP
    FOREACH q IN ARRAY ARRAY['SELECT * FROM public.red_person_purge_udbakke()',
      'SELECT public.red_person_purge_udbakke_kvitter(''purge-task12-a'',''en'')',
      'SELECT public.red_person_purge_udbakke_kvitter(''findes-ikke'',''findes-ikke'')'] LOOP
      BEGIN
        PERFORM pg_temp.km_antal(k,q);
        RAISE EXCEPTION 'TEST_FAILED udbakke_rollegate accepterede';
      EXCEPTION WHEN OTHERS THEN GET STACKED DIAGNOSTICS v_error=MESSAGE_TEXT,v_state=RETURNED_SQLSTATE;
      END;
      PERFORM pg_temp.udbakke_assert(CASE WHEN k='gaest' THEN v_state='42501' ELSE v_error='Kun redaktion' END,'udbakke_rollegate');
    END LOOP;
  END LOOP;
  PERFORM pg_temp.udbakke_assert(pg_temp.km_antal('redaktion','SELECT * FROM public.red_person_purge_udbakke()')=
    (SELECT count(*) FROM udbakke_foer),'udbakke_liste_redaktion');
  PERFORM pg_temp.km_antal('redaktion','SELECT public.red_person_purge_udbakke_kvitter(''purge-task12-a'',''en'')');
  -- EXCEPT i begge retninger sammenligner alle felter, også oprettet og rækken med samme sti i anden bucket.
  PERFORM pg_temp.udbakke_assert(NOT EXISTS (
    (SELECT * FROM private.person_purge_udbakke EXCEPT SELECT * FROM udbakke_foer WHERE NOT (bucket='purge-task12-a' AND sti='en'))
    UNION ALL
    (SELECT * FROM udbakke_foer WHERE NOT (bucket='purge-task12-a' AND sti='en') EXCEPT SELECT * FROM private.person_purge_udbakke)
  ),'udbakke_kvitter_praecis_en');
  PERFORM pg_temp.km_antal('redaktion','SELECT public.red_person_purge_udbakke_kvitter(''purge-task12-a'',''en'')');
  PERFORM pg_temp.udbakke_assert((SELECT count(*) FROM private.person_purge_udbakke)=(SELECT count(*)-1 FROM udbakke_foer),
    'udbakke_kvitter_idempotent');
END $t$;
ROLLBACK;
\echo OK udbakke_rollegate
\echo OK udbakke_acl
\echo OK udbakke_kvitter_praecis_en
\echo OK udbakke_kvitter_idempotent

-- Indsæt køposter EFTER de levende referencer: filteret skal også beskytte gamle/strandede køposter.
BEGIN;
\ir fixtures/kalder-matrix.sql
SELECT pg_temp.km_kaldere();
DO $t$
DECLARE v_media bigint;
BEGIN
  PERFORM purge_test.nyt();
  INSERT INTO public.media(bucket,storage_path,upload_status)
    VALUES('purge-task12-live','genbrugt-original','kladde') RETURNING id INTO v_media;
  INSERT INTO public.media_variant(media_id,tier,storage_path)
    VALUES(v_media,'thumb','genbrugt-variant');
  INSERT INTO private.person_purge_udbakke(bucket,sti) VALUES
    ('purge-task12-live','genbrugt-original'),('purge-task12-live','genbrugt-variant'),
    ('purge-task12-anden','genbrugt-original'),('purge-task12-anden','genbrugt-variant'),
    ('purge-task12-live','uden-reference');
  PERFORM pg_temp.udbakke_assert(pg_temp.km_antal('redaktion',
    $q$SELECT * FROM public.red_person_purge_udbakke()
      WHERE bucket='purge-task12-live' AND sti='genbrugt-original'$q$)=0,'udbakke_skjuler_levende_media');
  PERFORM pg_temp.udbakke_assert(pg_temp.km_antal('redaktion',
    $q$SELECT * FROM public.red_person_purge_udbakke()
      WHERE bucket='purge-task12-live' AND sti='genbrugt-variant'$q$)=0,'udbakke_skjuler_levende_variant');
  PERFORM pg_temp.udbakke_assert(pg_temp.km_antal('redaktion',
    $q$SELECT * FROM public.red_person_purge_udbakke()
      WHERE bucket='purge-task12-anden' AND sti='genbrugt-original'$q$)=1,
    'udbakke_media_anden_bucket_synlig');
  PERFORM pg_temp.udbakke_assert(pg_temp.km_antal('redaktion',
    $q$SELECT * FROM public.red_person_purge_udbakke()
      WHERE bucket='purge-task12-anden' AND sti='genbrugt-variant'$q$)=0,
    'udbakke_variant_alle_buckets_skjult');
  PERFORM pg_temp.udbakke_assert(pg_temp.km_antal('redaktion',
    $q$SELECT * FROM public.red_person_purge_udbakke()
      WHERE bucket='purge-task12-live' AND sti='uden-reference'$q$)=1,'udbakke_uden_reference_synlig');
END $t$;
ROLLBACK;
\echo OK udbakke_skjuler_levende_media
\echo OK udbakke_skjuler_levende_variant
\echo OK udbakke_media_anden_bucket_synlig
\echo OK udbakke_variant_alle_buckets_skjult
\echo OK udbakke_uden_reference_synlig

SET request.jwt.claim.sub='a2a00000-0000-4000-8000-00000000a001';
-- Tilføj en rigtig variant til det eksklusive medie, så begge slags bytes overlever i køen efter COMMIT.
INSERT INTO public.media_variant(media_id,tier,storage_path)
  VALUES(purge_test.id('medie_eksklusiv'),'thumb','purge-test/eksklusiv-genbrug-thumb.jpg');
-- Forventede bytes fra fixturens medie, ikke fra sletteinventaret eller manifestet.
CREATE TEMP TABLE udbakke_forventet AS
  SELECT 'media'::text AS art,m.bucket,m.storage_path AS sti FROM public.media m WHERE m.id=purge_test.id('medie_eksklusiv')
  UNION SELECT 'variant',m.bucket,v.storage_path FROM public.media_variant v JOIN public.media m ON m.id=v.media_id
    WHERE m.id=purge_test.id('medie_eksklusiv');
BEGIN;
SELECT public.red_slet_person_helt(purge_test.id('P'),public.red_slet_person_helt_preview(purge_test.id('P'))->>'sha256') \g /dev/null
COMMIT;
DO $t$
DECLARE cols text[];
BEGIN
  PERFORM pg_temp.udbakke_assert(NOT EXISTS(SELECT 1 FROM public.person WHERE id=purge_test.id('P')),'udbakke_efter_commit');
  PERFORM pg_temp.udbakke_assert(EXISTS(SELECT 1 FROM udbakke_forventet) AND NOT EXISTS (
    SELECT bucket,sti FROM udbakke_forventet EXCEPT SELECT bucket,sti FROM private.person_purge_udbakke),'udbakke_bytes_efter_commit');
  PERFORM pg_temp.udbakke_assert(NOT EXISTS (
    SELECT 1 FROM public.red_person_purge_udbakke() u WHERE
      (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(to_jsonb(u)) k) IS DISTINCT FROM ARRAY['bucket','oprettet','sti']
  ),'udbakke_liste_kun_tre_felter');
  SELECT array_agg(attname::text ORDER BY attname) INTO cols FROM pg_attribute
    WHERE attrelid='private.person_purge_udbakke'::regclass AND attnum>0 AND NOT attisdropped;
  PERFORM pg_temp.udbakke_assert(cols=ARRAY['bucket','oprettet','sti'] AND NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conrelid='private.person_purge_udbakke'::regclass AND contype='f'
  ) AND NOT EXISTS (SELECT 1 FROM private.person_purge_kandidatkolonner() k WHERE k.tabel='private.person_purge_udbakke'
    AND NOT EXISTS (SELECT 1 FROM private.person_purge_undtagelser() u WHERE u.tabel=k.tabel AND u.kolonne IN (k.kolonne,'*'))),
    'udbakke_ingen_person_reference');
  PERFORM pg_temp.udbakke_assert(NOT EXISTS (SELECT 1 FROM private.person_purge_udbakke
    WHERE sti LIKE '%'||purge_test.id('P')::text||'%' OR bucket LIKE '%'||purge_test.id('P')::text||'%'), 'udbakke_intet_person_id');
END $t$;
\echo OK udbakke_efter_commit
\echo OK udbakke_bytes_efter_commit
\echo OK udbakke_liste_kun_tre_felter
\echo OK udbakke_ingen_person_reference

-- Genbrug EFTER den rigtige sletnings COMMIT: kun de nye levende bytes annullerer køposter.
BEGIN;
DO $t$
DECLARE v_media bigint; v_variant bigint; v_original record; v_thumb record;
BEGIN
  SELECT bucket,sti INTO STRICT v_original FROM udbakke_forventet WHERE art='media';
  SELECT bucket,sti INTO STRICT v_thumb FROM udbakke_forventet WHERE art='variant';
  INSERT INTO private.person_purge_udbakke(bucket,sti) VALUES
    ('purge-task12-anden',v_original.sti),('purge-task12-anden',v_thumb.sti);
  PERFORM purge_test.nyt();
  INSERT INTO public.media(bucket,storage_path) VALUES(v_original.bucket,v_original.sti) RETURNING id INTO v_media;
  PERFORM pg_temp.udbakke_assert(NOT EXISTS (SELECT 1 FROM private.person_purge_udbakke
    WHERE bucket=v_original.bucket AND sti=v_original.sti) AND EXISTS (SELECT 1 FROM private.person_purge_udbakke
    WHERE bucket='purge-task12-anden' AND sti=v_original.sti),'udbakke_genbrug_media_efter_commit');
  -- En variant skal rydde alle buckets, også når dens nye forælder har en anden bucket.
  INSERT INTO public.media(bucket) VALUES('purge-task12-variant-foraelder') RETURNING id INTO v_media;
  INSERT INTO public.media_variant(media_id,tier,storage_path) VALUES(v_media,'thumb',v_thumb.sti)
    RETURNING id INTO v_variant;
  PERFORM pg_temp.udbakke_assert(NOT EXISTS (SELECT 1 FROM private.person_purge_udbakke WHERE sti=v_thumb.sti),
    'udbakke_genbrug_variant_efter_commit');

  -- UPDATE-vejene: bucket alene, media-sti alene og variant-sti alene.
  INSERT INTO private.person_purge_udbakke(bucket,sti) VALUES('purge-task12-opdateret',v_original.sti);
  UPDATE public.media SET bucket='purge-task12-opdateret'
    WHERE bucket=v_original.bucket AND storage_path=v_original.sti;
  PERFORM pg_temp.udbakke_assert(NOT EXISTS (SELECT 1 FROM private.person_purge_udbakke
    WHERE bucket='purge-task12-opdateret' AND sti=v_original.sti),'udbakke_genbrug_media_bucket_update');
  INSERT INTO private.person_purge_udbakke(bucket,sti) VALUES('purge-task12-opdateret','ny-media-sti');
  UPDATE public.media SET storage_path='ny-media-sti'
    WHERE bucket='purge-task12-opdateret' AND storage_path=v_original.sti;
  PERFORM pg_temp.udbakke_assert(NOT EXISTS (SELECT 1 FROM private.person_purge_udbakke
    WHERE bucket='purge-task12-opdateret' AND sti='ny-media-sti'),'udbakke_genbrug_media_sti_update');
  INSERT INTO private.person_purge_udbakke(bucket,sti) VALUES
    ('purge-task12-opdateret','ny-variant-sti'),('purge-task12-anden','ny-variant-sti');
  UPDATE public.media_variant SET storage_path='ny-variant-sti' WHERE id=v_variant;
  PERFORM pg_temp.udbakke_assert(NOT EXISTS (SELECT 1 FROM private.person_purge_udbakke WHERE sti='ny-variant-sti'),
    'udbakke_genbrug_variant_sti_update');
END $t$;
ROLLBACK;
\echo OK udbakke_genbrug_media_efter_commit
\echo OK udbakke_genbrug_variant_efter_commit
\echo OK udbakke_genbrug_media_bucket_update
\echo OK udbakke_genbrug_media_sti_update
\echo OK udbakke_genbrug_variant_sti_update

BEGIN;
DO $t$
DECLARE v_role text;
BEGIN
  FOREACH v_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    PERFORM pg_temp.udbakke_assert(NOT has_function_privilege(v_role,
      'private.person_purge_udbakke_genbrug()','EXECUTE'),'udbakke_genbrug_intern_acl');
  END LOOP;
  PERFORM pg_temp.udbakke_assert(NOT EXISTS (
    SELECT 1 FROM pg_proc p,aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a
    WHERE p.oid='private.person_purge_udbakke_genbrug()'::regprocedure AND a.grantee=0
      AND a.privilege_type='EXECUTE'),'udbakke_genbrug_intern_acl');
  FOREACH v_role IN ARRAY ARRAY['anon','authenticated'] LOOP
    BEGIN
      EXECUTE format('SET LOCAL ROLE %I',v_role);
      PERFORM private.person_purge_udbakke_genbrug();
      RAISE EXCEPTION 'TEST_FAILED udbakke_genbrug_klientkald accepterede';
    EXCEPTION WHEN insufficient_privilege THEN
      NULL; -- Kun 42501 accepteres; triggerfunktionens almindelige kaldfejl er ikke nok.
    END;
    RESET ROLE;
  END LOOP;
END $t$;
ROLLBACK;
\echo OK udbakke_genbrug_intern_acl
\echo OK udbakke_genbrug_klientkald_afvist
\endif

-- =====================================================================================================================
-- Review 37 P1+P2 (projektejeren 2026-11-20, løsning A): sletning af en IKKE-offentlig person må ikke gøre bevarede
-- billeder eller bevarede familiers indhold offentligt. Egne syntetiske personer i gruppens kopi; fixturens P (privat,
-- altså også ikke-offentlig) slettes ikke her, kun dens forhåndsvisning kontrolleres (den fulde sletning er gruppe purge).
--   L  levende, afbildet på M_eget (kun L, egen rettighedsfakta → bevares) og M_delt (L + afdød D), partner i fam_l
--      (+ afdød partner og barn → bevares).
--   B  levende BARN i fam_b (to afdøde forældre f1/f2 → bevares).
--   O  afdød/offentlig, afbildet på M_off (kun O, egen rettighedsfakta), partner i fam_o (+ barn).
-- Hver familie har vielse (påstand, citat, konklusion), note og familienarrativ; fam_l og fam_o desuden skilsmisse,
-- familiestory og en relation familie→ejendom. fam_l har også en TIDLIGERE vielse med L's navn i citatet, som er
-- fortrudt (findes kun i change_event; Codex-fund). Alle tre medier er 'klar' med maa_publiceres=true.
-- Projektejeren 2026-11-20: fam_b har desuden et familiefoto koblet DIREKTE til familien (M_famfoto; koblingen består,
-- billedet låses) og et vielsesfoto koblet KUN til vielsen (M_vielse; slettes helt inkl. storage).
-- Sletningerne COMMIT'es (udskudte triggere, V-4).
-- =====================================================================================================================
\if :g_purge_gdpr
SET request.jwt.claim.sub='a2a00000-0000-4000-8000-00000000a001';
CREATE FUNCTION pg_temp.gdpr_assert(p_ok boolean,p_test text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF p_ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'TEST_FAILED %',p_test; END IF; END $$;
CREATE TEMP TABLE gdpr_id(rolle text PRIMARY KEY, id bigint NOT NULL);
CREATE FUNCTION pg_temp.gid(p_rolle text) RETURNS bigint LANGUAGE sql STABLE AS $$
  SELECT id FROM pg_temp.gdpr_id WHERE rolle=p_rolle $$;
-- Én families post i forhåndsvisningens familieindhold_slettes (NULL hvis den ikke er der).
CREATE FUNCTION pg_temp.gdpr_fi(p_j jsonb,p_fam bigint) RETURNS jsonb LANGUAGE sql IMMUTABLE AS $$
  SELECT x FROM jsonb_array_elements(p_j->'familieindhold_slettes') x WHERE (x->>'family_id')::bigint=p_fam $$;
-- Familieindhold (fakta med evidenskæde, noter, narrativer, stories, relationer med familieende) for én familie.
-- En relation mellem et medie og familien er ikke familieindhold (projektejeren 2026-11-20); den kontrolleres for sig.
CREATE FUNCTION pg_temp.gdpr_indhold(p_fam bigint) RETURNS TABLE(tabel text,id bigint) LANGUAGE sql STABLE AS $$
  SELECT 'fact',f.id FROM public.fact f WHERE f.subjekt_type='family' AND f.subjekt_id=p_fam
  UNION ALL SELECT 'assertion',a.id FROM public.assertion a JOIN public.fact f ON a.target_type='fact' AND a.target_id=f.id
    WHERE f.subjekt_type='family' AND f.subjekt_id=p_fam
  UNION ALL SELECT 'citation',c.id FROM public.citation c JOIN public.assertion a ON a.id=c.assertion_id
    JOIN public.fact f ON a.target_type='fact' AND a.target_id=f.id WHERE f.subjekt_type='family' AND f.subjekt_id=p_fam
  UNION ALL SELECT 'conclusion',c.id FROM public.conclusion c JOIN public.fact f ON c.target_type='fact' AND c.target_id=f.id
    WHERE f.subjekt_type='family' AND f.subjekt_id=p_fam
  UNION ALL SELECT 'note',o.id FROM public.note o WHERE o.target_type='family' AND o.target_id=p_fam
  UNION ALL SELECT 'narrative',n.id FROM public.narrative n WHERE n.subjekt_type='family' AND n.subjekt_id=p_fam
  UNION ALL SELECT 'story',s.id FROM public.story s WHERE s.subjekt_type='family' AND s.subjekt_id=p_fam
  UNION ALL SELECT 'relation',r.id FROM public.relation r WHERE ((r.subjekt_type='family' AND r.subjekt_id=p_fam)
    OR (r.objekt_type='family' AND r.objekt_id=p_fam)) AND 'media' NOT IN (r.subjekt_type,r.objekt_type)
$$;
BEGIN;
DO $fix$
DECLARE v_fam bigint; v_m bigint; v_cs bigint; j jsonb; r record; f record;
BEGIN
  FOR r IN SELECT * FROM (VALUES ('L','Testperson Gdpr Levende','mand',true,'1960',NULL),
      ('D','Testperson Gdpr Afdød','kvinde',false,'1850','1910'),
      ('pa_l','Testperson Gdpr Partner','kvinde',false,'1955','2001'),('barn_l','Testperson Gdpr Barn','mand',false,'1980','2002'),
      ('O','Testperson Gdpr Offentlig','mand',false,'1840','1900'),
      ('pa_o','Testperson Gdpr Partner O','kvinde',false,'1842','1901'),('barn_o','Testperson Gdpr Barn O','kvinde',false,'1870','1930'),
      ('B','Testperson Gdpr Levende Barn','kvinde',true,'1990',NULL),
      ('f1','Testperson Gdpr Fader','mand',false,'1930','2000'),('f2','Testperson Gdpr Moder','kvinde',false,'1932','2005'))
    x(rolle,navn,koen,levende,foedt,doed) LOOP
    PERFORM purge_test.nyt();
    INSERT INTO pg_temp.gdpr_id VALUES (r.rolle,public.red_opret_person(r.navn,r.koen,r.levende,r.foedt,r.doed,NULL));
    -- red_opret_person opretter privat; her afgør kun levende offentligheden.
    PERFORM purge_test.nyt(); PERFORM public.red_set_privat(pg_temp.gid(r.rolle),false);
  END LOOP;
  -- Familier med barn, så de bevares (Fam_keep), med familieindhold.
  FOR f IN SELECT * FROM (VALUES ('l','L','pa_l','barn_l',true),('o','O','pa_o','barn_o',true),('b','f1','f2','B',false))
    x(k,a,b,barn,fuld) LOOP
    PERFORM purge_test.nyt();
    v_fam:=public.red_opret_union(pg_temp.gid(f.a),pg_temp.gid(f.b),'vielse',1);
    INSERT INTO pg_temp.gdpr_id VALUES ('fam_'||f.k,v_fam);
    PERFORM purge_test.nyt();
    PERFORM public.red_tilfoej_barn(v_fam,pg_temp.gid(f.barn));
    IF f.k='l' THEN
      -- Codex-fund: en tidligere vielse med L's navn i citatet, fortrudt; findes derefter kun i change_event.
      PERFORM purge_test.nyt();
      j:=public.red_opret_fakta('family',v_fam,'vielse','1984',p_date_raw=>'1984',
        p_kilde_fritekst=>'g. 1984 m. Testperson Gdpr Levende');
      v_cs:=purge_test.saet();
      INSERT INTO pg_temp.gdpr_id VALUES ('vielse_gl',(j->>'fact_id')::bigint),('saet_gl',v_cs);
      PERFORM purge_test.nyt();
      PERFORM public.red_fortryd_change_set(v_cs,false);
    END IF;
    PERFORM purge_test.nyt();
    j:=public.red_opret_fakta('family',v_fam,'vielse','1985',p_date_raw=>'1985',p_kilde_fritekst=>'Syntetisk vielseskilde');
    INSERT INTO pg_temp.gdpr_id VALUES ('vielse_'||f.k,(j->>'fact_id')::bigint);
    PERFORM purge_test.nyt(); PERFORM public.begin_change_set('gdpr_familieindhold','fixture','family',v_fam);
    WITH x AS (INSERT INTO public.note(target_type,target_id,indhold) VALUES ('family',v_fam,'Syntetisk familienote') RETURNING id)
    INSERT INTO pg_temp.gdpr_id SELECT 'note_'||f.k,id FROM x;
    WITH x AS (INSERT INTO public.narrative(subjekt_type,subjekt_id,tekst) VALUES ('family',v_fam,'Syntetisk familiebiografi') RETURNING id)
    INSERT INTO pg_temp.gdpr_id SELECT 'narr_'||f.k,id FROM x;
    IF f.fuld THEN
      PERFORM purge_test.nyt();
      j:=public.red_opret_fakta('family',v_fam,'skilsmisse','1999',p_date_raw=>'1999',p_kilde_fritekst=>'Syntetisk kilde');
      INSERT INTO pg_temp.gdpr_id VALUES ('skilsmisse_'||f.k,(j->>'fact_id')::bigint);
      PERFORM purge_test.nyt();
      INSERT INTO pg_temp.gdpr_id VALUES ('story_'||f.k,public.red_opret_story('family',v_fam,'Syntetisk familiehistorie','Familien'));
      PERFORM purge_test.nyt();
      INSERT INTO pg_temp.gdpr_id VALUES ('rel_'||f.k,public.red_relation('family',v_fam,'estate',purge_test.id('ejendom'),'ejer'));
    END IF;
  END LOOP;
  -- Medier: frigivet ('klar' + maa_publiceres). M_eget/M_off har egne fakta (rettigheder) og bevares derfor (S37b).
  FOR r IN SELECT * FROM (VALUES ('m_eget','L','gdpr-test/eget.jpg',true),('m_delt','L','gdpr-test/delt.jpg',false),
      ('m_off','O','gdpr-test/off.jpg',true)) x(rolle,afbildet,sti,egne_fakta) LOOP
    PERFORM purge_test.nyt();
    v_m:=public.red_upload_media('foto','Syntetisk billede',r.sti,'image/jpeg',p_afbildet_person_id=>pg_temp.gid(r.afbildet),
      p_maa_publiceres=>true);
    INSERT INTO pg_temp.gdpr_id VALUES (r.rolle,v_m);
    PERFORM purge_test.nyt(); PERFORM public.red_bekraeft_media_upload(v_m);
    IF r.egne_fakta THEN
      PERFORM purge_test.nyt(); PERFORM public.red_set_media_rettigheder(v_m,'frigivet',true,p_licens=>'CC BY 4.0');
    END IF;
  END LOOP;
  PERFORM purge_test.nyt();
  PERFORM public.red_relation('person',pg_temp.gid('D'),'media',pg_temp.gid('m_delt'),'afbildet');
  -- Familiefoto direkte på fam_b og vielsesfoto kun på vielse_b, begge via upload-RPC'en (media→mål, 'afbildet').
  FOR r IN SELECT * FROM (VALUES ('famfoto','family','fam_b','gdpr-test/familie.jpg'),('vielse','fact','vielse_b','gdpr-test/vielse.jpg'))
      x(k,typ,maal,sti) LOOP
    PERFORM purge_test.nyt();
    v_m:=public.red_upload_media('foto','Syntetisk billede',r.sti,'image/jpeg',p_objekt_type=>r.typ,p_objekt_id=>pg_temp.gid(r.maal),
      p_maa_publiceres=>true);
    INSERT INTO pg_temp.gdpr_id VALUES ('m_'||r.k,v_m);
    INSERT INTO pg_temp.gdpr_id SELECT 'rel_m_'||r.k,id FROM public.relation
      WHERE subjekt_type='media' AND subjekt_id=v_m AND objekt_type=r.typ AND objekt_id=pg_temp.gid(r.maal);
    PERFORM purge_test.nyt(); PERFORM public.red_bekraeft_media_upload(v_m);
  END LOOP;
  -- Runde 4, F (projektejeren godkendt): forslag på fakta og relationer, der slettes, slettes også for en OFFENTLIG
  -- person (O): på O's fødselsfaktum og på O's afbildet-relation. Et forslag på den bevarede fam_o's vielse står.
  PERFORM purge_test.nyt();
  INSERT INTO pg_temp.gdpr_id VALUES ('forslag_o_fakta',public.red_suggest('rettelse','fact',(SELECT id FROM public.fact
      WHERE subjekt_type='person' AND subjekt_id=pg_temp.gid('O') AND faktatype='fødsel'),'vaerdi','1841',NULL,'{}'::jsonb,'Syntetisk')),
    ('forslag_o_rel',public.red_suggest('rettelse','relation',(SELECT id FROM public.relation WHERE subjekt_type='person'
      AND subjekt_id=pg_temp.gid('O') AND objekt_type='media'),'rolle','afbildet',NULL,'{}'::jsonb,'Syntetisk')),
    ('forslag_o_vielse',public.red_suggest('rettelse','fact',pg_temp.gid('vielse_o'),'vaerdi','1866',NULL,'{}'::jsonb,'Syntetisk'));
  -- Sikkerhedsfund til den bevarede kobling: evidenskæde (påstand, citat, konklusion), en note og et forslag på den.
  PERFORM purge_test.nyt();
  PERFORM public.begin_change_set('gdpr_koblingsevidens','fixture','family',pg_temp.gid('fam_b'));
  INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst) VALUES ('relation',pg_temp.gid('rel_m_famfoto'),'Syntetisk familiefoto')
    RETURNING id INTO v_m;
  INSERT INTO pg_temp.gdpr_id VALUES ('kob_assertion',v_m),('kob_saet',purge_test.saet());
  WITH x AS (INSERT INTO public.conclusion(target_type,target_id,valgt_assertion_id,status)
    VALUES ('relation',pg_temp.gid('rel_m_famfoto'),v_m,'afklaret') RETURNING id) INSERT INTO pg_temp.gdpr_id SELECT 'kob_conclusion',id FROM x;
  WITH x AS (INSERT INTO public.citation(assertion_id,source_id,citat_tekst,side)
    VALUES (v_m,purge_test.id('kilde_b'),'Syntetisk billedkilde','1') RETURNING id) INSERT INTO pg_temp.gdpr_id SELECT 'kob_citation',id FROM x;
  PERFORM purge_test.nyt();
  PERFORM public.begin_change_set('gdpr_koblingsnote','fixture','family',pg_temp.gid('fam_b'));
  WITH x AS (INSERT INTO public.note(target_type,target_id,indhold)
    VALUES ('relation',pg_temp.gid('rel_m_famfoto'),'Syntetisk note: Testperson Gdpr Levende Barn står yderst') RETURNING id)
  INSERT INTO pg_temp.gdpr_id SELECT 'kob_note',id FROM x;
  INSERT INTO pg_temp.gdpr_id VALUES ('kob_note_saet',purge_test.saet());
  PERFORM purge_test.nyt();
  INSERT INTO pg_temp.gdpr_id VALUES ('kob_forslag',public.red_suggest('rettelse','relation',pg_temp.gid('rel_m_famfoto'),'rolle',
    'afbildet',NULL,'{}'::jsonb,'Forslag: Testperson Gdpr Levende Barn står yderst'));
  -- Codex runde 4 (fund B): note og forslag på en relation til familiens FAKTUM (vielsesfotoets kobling til vielse_b).
  PERFORM purge_test.nyt();
  PERFORM public.begin_change_set('gdpr_vielsesfoto_note','fixture','family',pg_temp.gid('fam_b'));
  WITH x AS (INSERT INTO public.note(target_type,target_id,indhold) VALUES ('relation',pg_temp.gid('rel_m_vielse'),'Syntetisk billednote')
    RETURNING id) INSERT INTO pg_temp.gdpr_id SELECT 'vfoto_note',id FROM x;
  PERFORM purge_test.nyt();
  INSERT INTO pg_temp.gdpr_id VALUES ('vfoto_forslag',public.red_suggest('rettelse','relation',pg_temp.gid('rel_m_vielse'),'rolle',
    'afbildet',NULL,'{}'::jsonb,'Syntetisk billedforslag'));
  -- Codex-fund B: levende Q er barn i fam_s (kun en story), partner i fam_r (kun en relation familie→ejendom) og i fam_h
  -- (kun historik: en story, der er fortrudt). Alle tre bevares (afdøde partner/forældre og barn).
  FOR r IN SELECT * FROM (VALUES ('Q','Testperson Gdpr Kun','kvinde',true,'1992',NULL),
      ('q_pa','Testperson Gdpr Q Partner','mand',false,'1900','1970'),('q_barn','Testperson Gdpr Q Barn','mand',false,'1930','1990'),
      ('q_barn2','Testperson Gdpr Q Barn To','kvinde',false,'1932','1995'),
      ('q_barn3','Testperson Gdpr Q Barn Tre','mand',false,'1934','1996'),
      ('q_f1','Testperson Gdpr Q Fader','mand',false,'1901','1980'),('q_f2','Testperson Gdpr Q Moder','kvinde',false,'1903','1985'))
    x(rolle,navn,koen,levende,foedt,doed) LOOP
    PERFORM purge_test.nyt();
    INSERT INTO pg_temp.gdpr_id VALUES (r.rolle,public.red_opret_person(r.navn,r.koen,r.levende,r.foedt,r.doed,NULL));
    PERFORM purge_test.nyt(); PERFORM public.red_set_privat(pg_temp.gid(r.rolle),false);
  END LOOP;
  FOR f IN SELECT * FROM (VALUES ('s','q_f1','q_f2','Q',1),('r','Q','q_pa','q_barn',1),('h','Q','q_pa','q_barn2',2),('k','Q','q_pa','q_barn3',3))
    x(k,a,b,barn,ord) LOOP
    PERFORM purge_test.nyt();
    v_fam:=public.red_opret_union(pg_temp.gid(f.a),pg_temp.gid(f.b),'vielse',f.ord);
    INSERT INTO pg_temp.gdpr_id VALUES ('fam_q'||f.k,v_fam);
    PERFORM purge_test.nyt(); PERFORM public.red_tilfoej_barn(v_fam,pg_temp.gid(f.barn));
    PERFORM purge_test.nyt();
    IF f.k='s' THEN
      INSERT INTO pg_temp.gdpr_id VALUES ('story_qs',public.red_opret_story('family',v_fam,'Syntetisk familiehistorie','Familien'));
    ELSIF f.k='r' THEN
      INSERT INTO pg_temp.gdpr_id VALUES ('rel_qr',public.red_relation('family',v_fam,'estate',purge_test.id('ejendom'),'ejer'));
    ELSIF f.k='h' THEN
      PERFORM public.red_opret_story('family',v_fam,'Syntetisk tidligere historie','Familien');
      v_cs:=purge_test.saet();
      PERFORM purge_test.nyt(); PERFORM public.red_fortryd_change_set(v_cs,false);
    ELSE
      -- Codex runde 4 (fund B): kun en bevaret familiefoto-kobling og historik fra en tidligere (fortrudt) note på den.
      v_m:=public.red_upload_media('foto','Syntetisk billede','gdpr-test/q-familie.jpg','image/jpeg',p_objekt_type=>'family',
        p_objekt_id=>v_fam,p_maa_publiceres=>true);
      INSERT INTO pg_temp.gdpr_id VALUES ('m_qk',v_m);
      PERFORM purge_test.nyt(); PERFORM public.red_bekraeft_media_upload(v_m);
      PERFORM purge_test.nyt();
      PERFORM public.begin_change_set('gdpr_koblingsnote_gl','fixture','family',v_fam);
      INSERT INTO public.note(target_type,target_id,indhold)
        SELECT 'relation',id,'Syntetisk tidligere note' FROM public.relation WHERE subjekt_type='media' AND subjekt_id=v_m;
      v_cs:=purge_test.saet();
      PERFORM purge_test.nyt(); PERFORM public.red_fortryd_change_set(v_cs,false);
    END IF;
  END LOOP;
  -- Codex-fund A: en kurateret hændelse (feed-dom) på et narrativ, der siden er væk, for fam_l og for L selv. fam_l:
  -- narrativet fortrydes (fortrydelsen logger ingen events). L: narrativet slettes i et sæt uden subjekt (som en ældre
  -- sletning), så hændelsens kaskadesletning logges dér. Hændelsen findes derefter kun i change_event, hvis snapshot kun
  -- har id+feed_status (version_pk_registry).
  FOR f IN SELECT * FROM (VALUES ('fam','family','fam_l'),('pers','person','L')) x(k,typ,ejer) LOOP
    PERFORM purge_test.nyt();
    v_fam:=public.red_upsert_narrativ(f.typ,pg_temp.gid(f.ejer),'Syntetisk tidligere narrativ',false,purge_test.id('kilde_b'),'1');
    v_cs:=purge_test.saet();
    INSERT INTO pg_temp.gdpr_id VALUES ('hnarr_'||f.k,v_fam),('hnarr_saet_'||f.k,v_cs);
    PERFORM purge_test.nyt();  -- hændelser indlæses uden sæt (som load_haendelser.R)
    INSERT INTO public.haendelse(subjekt_type,subjekt_id,narrative_id,noegle,klausul,kategori,date_raw)
      VALUES (f.typ,pg_temp.gid(f.ejer),v_fam,'gdpr-h-'||f.k,'Syntetisk hændelse 1990','andet','1990') RETURNING id INTO v_m;
    INSERT INTO pg_temp.gdpr_id VALUES ('h_'||f.k,v_m);
    PERFORM purge_test.nyt(); PERFORM public.red_set_haendelse_status(v_m,'interessant');
    INSERT INTO pg_temp.gdpr_id VALUES ('h_status_saet_'||f.k,purge_test.saet());
    -- Runde 4, punkt C: en levende feed-pin på hændelsen, som overlever hændelsen.
    PERFORM purge_test.nyt(); PERFORM public.red_set_feed_pin('arkiv:'||v_m,'pin');
    PERFORM purge_test.nyt();
    IF f.k='fam' THEN
      PERFORM public.red_fortryd_change_set(v_cs,false);
    ELSE
      PERFORM public.begin_change_set('gdpr_tidligere_slettet','fixture',NULL,NULL);
      DELETE FROM public.narrative WHERE id=v_fam;
      INSERT INTO pg_temp.gdpr_id VALUES ('h_slet_saet_'||f.k,purge_test.saet());
    END IF;
  END LOOP;
  -- Codex runde 4 (fund A): to feed-domme i SAMME transaktion, først på L's hændelse, så på D's. begin_change_set genbruger
  -- det åbne sæt, så sættet har L som subjekt, men rummer også D's event. D's narrativ fortrydes bagefter, så D's
  -- hændelse kun findes i historikken. Sletningen af L må ikke tage D's historik med.
  FOR f IN SELECT * FROM (VALUES ('l','L','2'),('d','D','3')) x(k,ejer,side) LOOP
    PERFORM purge_test.nyt();
    v_fam:=public.red_upsert_narrativ('person',pg_temp.gid(f.ejer),'Syntetisk narrativ med hændelse',false,purge_test.id('kilde_b'),f.side);
    INSERT INTO pg_temp.gdpr_id VALUES ('mix_narr_saet_'||f.k,purge_test.saet());
    PERFORM purge_test.nyt();
    INSERT INTO public.haendelse(subjekt_type,subjekt_id,narrative_id,noegle,klausul,kategori,date_raw)
      VALUES ('person',pg_temp.gid(f.ejer),v_fam,'gdpr-mix-'||f.k,'Syntetisk hændelse 1991','andet','1991') RETURNING id INTO v_m;
    INSERT INTO pg_temp.gdpr_id VALUES ('mix_h_'||f.k,v_m);
  END LOOP;
  PERFORM purge_test.nyt();
  PERFORM public.red_set_haendelse_status(pg_temp.gid('mix_h_l'),'interessant');
  PERFORM public.red_set_haendelse_status(pg_temp.gid('mix_h_d'),'skjult');
  INSERT INTO pg_temp.gdpr_id VALUES ('mix_saet',purge_test.saet());
  PERFORM purge_test.nyt(); PERFORM public.red_fortryd_change_set(pg_temp.gid('mix_narr_saet_d'),false);
  -- Codex runde 5: modstridende bevis. Hændelsen får feed-dom under L, FLYTTES (simuleret med direkte UPDATE uden sæt;
  -- ingen skriver kan i dag) til D's narrativ, får feed-dom under D og en feed-pin, og D's narrativ fortrydes. Ejerskabet
  -- er tvetydigt; sletningen af L skal lade begge domme og pin'en stå.
  PERFORM purge_test.nyt();
  v_fam:=public.red_upsert_narrativ('person',pg_temp.gid('L'),'Syntetisk narrativ før flytning',false,purge_test.id('kilde_b'),'4');
  PERFORM purge_test.nyt();
  INSERT INTO public.haendelse(subjekt_type,subjekt_id,narrative_id,noegle,klausul,kategori,date_raw)
    VALUES ('person',pg_temp.gid('L'),v_fam,'gdpr-flyt','Syntetisk hændelse 1992','andet','1992') RETURNING id INTO v_m;
  INSERT INTO pg_temp.gdpr_id VALUES ('flyt_h',v_m);
  PERFORM purge_test.nyt(); PERFORM public.red_set_haendelse_status(v_m,'interessant');
  INSERT INTO pg_temp.gdpr_id VALUES ('flyt_dom_l',purge_test.saet());
  PERFORM purge_test.nyt();
  v_fam:=public.red_upsert_narrativ('person',pg_temp.gid('D'),'Syntetisk narrativ efter flytning',false,purge_test.id('kilde_b'),'5');
  INSERT INTO pg_temp.gdpr_id VALUES ('flyt_narr_saet_d',purge_test.saet());
  PERFORM purge_test.nyt();
  UPDATE public.haendelse SET subjekt_id=pg_temp.gid('D'),narrative_id=v_fam WHERE id=v_m;
  PERFORM purge_test.nyt(); PERFORM public.red_set_haendelse_status(v_m,'skjult');
  INSERT INTO pg_temp.gdpr_id VALUES ('flyt_dom_d',purge_test.saet());
  PERFORM purge_test.nyt(); PERFORM public.red_set_feed_pin('arkiv:'||v_m,'pin');
  PERFORM purge_test.nyt(); PERFORM public.red_fortryd_change_set(pg_temp.gid('flyt_narr_saet_d'),false);
  PERFORM purge_test.nyt();
END $fix$;
COMMIT;

-- Udgangspunktet: kun de afbildede/familiemedlemmerne holder billeder og familieindhold skjult.
DO $t$
BEGIN
  PERFORM pg_temp.gdpr_assert(NOT public.person_offentlig(pg_temp.gid('L')) AND NOT public.person_offentlig(pg_temp.gid('B'))
    AND public.person_offentlig(pg_temp.gid('O')) AND public.person_offentlig(pg_temp.gid('D')),'gdpr_fixture_offentlighed');
  PERFORM pg_temp.gdpr_assert((SELECT bool_and(maa_publiceres AND upload_status='klar') FROM public.media
    WHERE id IN (pg_temp.gid('m_eget'),pg_temp.gid('m_delt'),pg_temp.gid('m_off'),pg_temp.gid('m_famfoto'),pg_temp.gid('m_vielse')))
    AND pg_temp.gid('rel_m_famfoto') IS NOT NULL AND pg_temp.gid('rel_m_vielse') IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM public.fact WHERE subjekt_type='media'
      AND subjekt_id IN (pg_temp.gid('m_famfoto'),pg_temp.gid('m_vielse'))),'gdpr_fixture_frigivet');
  PERFORM pg_temp.gdpr_assert(EXISTS (SELECT 1 FROM public.fact WHERE subjekt_type='media' AND subjekt_id=pg_temp.gid('m_eget'))
    AND EXISTS (SELECT 1 FROM public.fact WHERE subjekt_type='media' AND subjekt_id=pg_temp.gid('m_off')),'gdpr_fixture_egne_fakta');
  PERFORM pg_temp.gdpr_assert(NOT public.media_synlig_anon(pg_temp.gid('m_eget')) AND NOT public.media_synlig_anon(pg_temp.gid('m_delt'))
    AND public.media_synlig_anon(pg_temp.gid('m_off')),'gdpr_fixture_synlighed_foer');
  PERFORM pg_temp.gdpr_assert(NOT public.family_offentlig(pg_temp.gid('fam_l')) AND NOT public.family_offentlig(pg_temp.gid('fam_b'))
    AND public.family_offentlig(pg_temp.gid('fam_o')),'gdpr_fixture_familie_foer');
  -- Hver familie har sit indhold; fam_l/fam_o det fulde sæt (fakta+evidens, note, narrativ, story, relation).
  PERFORM pg_temp.gdpr_assert((SELECT count(DISTINCT tabel) FROM pg_temp.gdpr_indhold(pg_temp.gid('fam_l')))=8
    AND (SELECT count(DISTINCT tabel) FROM pg_temp.gdpr_indhold(pg_temp.gid('fam_o')))=8
    AND (SELECT count(DISTINCT tabel) FROM pg_temp.gdpr_indhold(pg_temp.gid('fam_b')))=6,'gdpr_fixture_familieindhold');
  -- Den fortrudte vielse findes kun i historikken.
  PERFORM pg_temp.gdpr_assert(NOT EXISTS (SELECT 1 FROM public.fact WHERE id=pg_temp.gid('vielse_gl'))
    AND EXISTS (SELECT 1 FROM public.change_set WHERE reverterer_id=pg_temp.gid('saet_gl'))
    AND EXISTS (SELECT 1 FROM public.change_event WHERE tabel='citation'
      AND position('Testperson Gdpr Levende' IN coalesce(foer::text,efter::text))>0),'gdpr_fixture_fortrudt_vielse');
END $t$;
-- Codex-fund A, udgangspunkt: hændelserne er væk, men deres feed-dom og kaskadesletning står i historikken.
DO $t$
BEGIN
  PERFORM pg_temp.gdpr_assert((SELECT bool_and(NOT EXISTS (SELECT 1 FROM public.haendelse WHERE id=pg_temp.gid('h_'||k))
      AND NOT EXISTS (SELECT 1 FROM public.narrative WHERE id=pg_temp.gid('hnarr_'||k))
      AND EXISTS (SELECT 1 FROM public.change_event WHERE tabel='haendelse' AND op='UPDATE'
        AND change_set_id=pg_temp.gid('h_status_saet_'||k) AND row_pk->>'id'=pg_temp.gid('h_'||k)::text)
      AND (k='fam' OR EXISTS (SELECT 1 FROM public.change_event e JOIN public.change_set cs ON cs.id=e.change_set_id
        WHERE cs.id=pg_temp.gid('h_slet_saet_'||k) AND cs.subjekt_type IS NULL AND e.tabel='haendelse' AND e.op='DELETE'
          AND e.row_pk->>'id'=pg_temp.gid('h_'||k)::text))
      AND (k='pers' OR EXISTS (SELECT 1 FROM public.change_set WHERE reverterer_id=pg_temp.gid('hnarr_saet_'||k)))
      AND NOT EXISTS (SELECT 1 FROM public.change_event WHERE tabel='haendelse' AND row_pk->>'id'=pg_temp.gid('h_'||k)::text
        AND (foer ? 'subjekt_id' OR efter ? 'subjekt_id' OR foer ? 'narrative_id' OR efter ? 'narrative_id')))
    FROM unnest(ARRAY['fam','pers']) k)
    AND (SELECT count(*) FROM public.feed_pin WHERE kort_noegle IN ('arkiv:'||pg_temp.gid('h_fam'),'arkiv:'||pg_temp.gid('h_pers')))=2,
    'gdpr_fixture_tidligere_haendelse');
END $t$;
-- Codex runde 4: det blandede sæt har L som subjekt og begge hændelsers events; D's hændelse er væk.
DO $t$
BEGIN
  PERFORM pg_temp.gdpr_assert(EXISTS (SELECT 1 FROM public.change_set WHERE id=pg_temp.gid('mix_saet') AND subjekt_type='person'
      AND subjekt_id=pg_temp.gid('L') AND operation='red_set_haendelse_status')
    AND (SELECT count(*) FROM public.change_event WHERE change_set_id=pg_temp.gid('mix_saet') AND tabel='haendelse')=2
    AND NOT EXISTS (SELECT 1 FROM public.haendelse WHERE id=pg_temp.gid('mix_h_d'))
    AND EXISTS (SELECT 1 FROM public.haendelse WHERE id=pg_temp.gid('mix_h_l')),'gdpr_fixture_blandet_saet');
END $t$;
\echo OK gdpr_fixture

-- Forhåndsvisningerne gemmes FØR sletningerne; de kontrolleres nederst.
CREATE TEMP TABLE gdpr_preview AS
  SELECT 'L'::text AS hvem,public.red_slet_person_helt_preview(pg_temp.gid('L')) AS j
  UNION ALL SELECT 'B',public.red_slet_person_helt_preview(pg_temp.gid('B'))
  UNION ALL SELECT 'O',public.red_slet_person_helt_preview(pg_temp.gid('O'))
  UNION ALL SELECT 'P',public.red_slet_person_helt_preview(purge_test.id('P'))
  UNION ALL SELECT 'Q',public.red_slet_person_helt_preview(pg_temp.gid('Q'));
-- Familieindholdet, målt før sletningerne.
CREATE TEMP TABLE gdpr_indhold_foer AS
  SELECT k AS fam,i.tabel,i.id FROM unnest(ARRAY['fam_l','fam_o','fam_b']) k CROSS JOIN LATERAL pg_temp.gdpr_indhold(pg_temp.gid(k)) i;
-- Den fortrudte vielses historik: oprettelsessættet, fortrydelsessættet og alle deres events.
CREATE TEMP TABLE gdpr_hist_gl AS
  SELECT 'change_set'::text AS tabel,cs.id FROM public.change_set cs
    WHERE cs.id=pg_temp.gid('saet_gl') OR cs.reverterer_id=pg_temp.gid('saet_gl')
  UNION ALL SELECT 'change_event',e.id FROM public.change_event e JOIN public.change_set cs ON cs.id=e.change_set_id
    WHERE cs.id=pg_temp.gid('saet_gl') OR cs.reverterer_id=pg_temp.gid('saet_gl');
-- Codex-fund A: narrativsættet, feed-dommen, fortrydelsen og alle deres events.
CREATE TEMP TABLE gdpr_hist_h AS
  WITH saet AS (SELECT cs.id FROM public.change_set cs, unnest(ARRAY['fam','pers']) k
    WHERE cs.id IN (pg_temp.gid('hnarr_saet_'||k),pg_temp.gid('h_status_saet_'||k),pg_temp.gid('h_slet_saet_'||k))
      OR cs.reverterer_id=pg_temp.gid('hnarr_saet_'||k))
  SELECT 'change_set'::text AS tabel,id FROM saet
  UNION ALL SELECT 'change_event',e.id FROM public.change_event e WHERE e.change_set_id IN (SELECT id FROM saet);
CREATE TEMP TABLE gdpr_history AS SELECT 'change_set' tabel,id FROM public.change_set
  UNION ALL SELECT 'change_event',id FROM public.change_event;
CREATE TEMP TABLE gdpr_medlemmer AS SELECT family_id,person_id,rolle FROM public.family_member
  WHERE family_id IN (pg_temp.gid('fam_l'),pg_temp.gid('fam_b'),pg_temp.gid('fam_o'));

-- Sikkerhedsfund: den bevarede evidens på familiefoto-koblingen er stadig omfattet af token-blokeringen (S29). Prøves i en
-- transaktion, der rulles tilbage: et [[person:B|…]]-link i citatet eller påstanden blokerer sletningen af B.
BEGIN;
UPDATE public.citation SET citat_tekst='Syntetisk billedkilde [[person:'||pg_temp.gid('B')||'|B]]' WHERE id=pg_temp.gid('kob_citation');
UPDATE public.assertion SET vaerdi_tekst='Syntetisk familiefoto [[person:'||pg_temp.gid('B')||'|B]]' WHERE id=pg_temp.gid('kob_assertion');
DO $t$
DECLARE b jsonb:=public.red_slet_person_helt_preview(pg_temp.gid('B'));
BEGIN
  PERFORM pg_temp.gdpr_assert(EXISTS (SELECT 1 FROM jsonb_array_elements(b->'blokeringer') x WHERE x->>'art'='link_i_tekst'
      AND x->>'tabel'='citation' AND x->'pk'=jsonb_build_object('id',pg_temp.gid('kob_citation')))
    AND EXISTS (SELECT 1 FROM jsonb_array_elements(b->'blokeringer') x WHERE x->>'art'='link_i_tekst'
      AND x->>'tabel'='assertion' AND x->'pk'=jsonb_build_object('id',pg_temp.gid('kob_assertion'))),'gdpr_kobling_evidens_token_blokerer');
END $t$;
ROLLBACK;
\echo OK gdpr_kobling_evidens_token_blokerer

-- Sletning af den levende L og det levende barn B.
BEGIN;
DO $t$
DECLARE v_hash text:=(SELECT j->>'sha256' FROM gdpr_preview WHERE hvem='L'); v_id bigint:=pg_temp.gid('L');
BEGIN
  SET LOCAL ROLE authenticated;
  PERFORM public.red_slet_person_helt(v_id,v_hash);
  RESET ROLE;
END $t$;
COMMIT;
BEGIN;
DO $t$
DECLARE v_hash text:=(SELECT j->>'sha256' FROM gdpr_preview WHERE hvem='B'); v_id bigint:=pg_temp.gid('B');
BEGIN
  SET LOCAL ROLE authenticated;
  PERFORM public.red_slet_person_helt(v_id,v_hash);
  RESET ROLE;
END $t$;
COMMIT;
DO $t$
BEGIN
  PERFORM pg_temp.gdpr_assert(NOT EXISTS (SELECT 1 FROM public.person WHERE id IN (pg_temp.gid('L'),pg_temp.gid('B'))),
    'gdpr_levende_slettet');
  PERFORM pg_temp.gdpr_assert(NOT EXISTS (SELECT 1 FROM private.person_purge_manifest),'gdpr_levende_manifest_tomt');
END $t$;
-- Medie-lås: bevaret, ikke længere frigivet, usynligt for anon.
DO $t$
BEGIN
  PERFORM pg_temp.gdpr_assert(EXISTS (SELECT 1 FROM public.media WHERE id=pg_temp.gid('m_eget') AND NOT maa_publiceres
      AND upload_status='klar')
    AND EXISTS (SELECT 1 FROM public.fact WHERE subjekt_type='media' AND subjekt_id=pg_temp.gid('m_eget'))
    AND NOT public.media_synlig_anon(pg_temp.gid('m_eget')),'gdpr_levende_eget_medie_laast');
END $t$;
\echo OK gdpr_levende_eget_medie_laast
DO $t$
BEGIN
  PERFORM pg_temp.gdpr_assert(EXISTS (SELECT 1 FROM public.media WHERE id=pg_temp.gid('m_delt') AND NOT maa_publiceres)
    AND EXISTS (SELECT 1 FROM public.relation WHERE subjekt_type='person' AND subjekt_id=pg_temp.gid('D') AND rolle='afbildet'
      AND objekt_type='media' AND objekt_id=pg_temp.gid('m_delt'))
    AND NOT public.media_synlig_anon(pg_temp.gid('m_delt')),'gdpr_levende_delt_medie_laast');
END $t$;
\echo OK gdpr_levende_delt_medie_laast
-- Løsning A, partner: ALT familieindhold på fam_l er væk (vielse, skilsmisse med evidens, note, narrativ, story,
-- relation); familien og de øvrige medlemskaber består.
DO $t$
BEGIN
  PERFORM pg_temp.gdpr_assert(NOT EXISTS (SELECT 1 FROM pg_temp.gdpr_indhold(pg_temp.gid('fam_l'))),'gdpr_partner_familieindhold_slettet');
  PERFORM pg_temp.gdpr_assert(NOT EXISTS (SELECT 1 FROM gdpr_indhold_foer v WHERE v.fam='fam_l' AND (
      (v.tabel='fact' AND EXISTS (SELECT 1 FROM public.fact WHERE id=v.id))
      OR (v.tabel='assertion' AND EXISTS (SELECT 1 FROM public.assertion WHERE id=v.id))
      OR (v.tabel='citation' AND EXISTS (SELECT 1 FROM public.citation WHERE id=v.id))
      OR (v.tabel='conclusion' AND EXISTS (SELECT 1 FROM public.conclusion WHERE id=v.id)))),'gdpr_partner_familieindhold_slettet');
END $t$;
\echo OK gdpr_partner_familieindhold_slettet
DO $t$
BEGIN
  PERFORM pg_temp.gdpr_assert(EXISTS (SELECT 1 FROM public.family WHERE id=pg_temp.gid('fam_l'))
    AND public.family_offentlig(pg_temp.gid('fam_l'))
    AND NOT EXISTS (SELECT family_id,person_id,rolle FROM gdpr_medlemmer WHERE family_id=pg_temp.gid('fam_l')
      AND person_id<>pg_temp.gid('L') EXCEPT SELECT family_id,person_id,rolle FROM public.family_member),
    'gdpr_partner_familie_bevaret');
END $t$;
\echo OK gdpr_partner_familie_bevaret
-- Løsning A, barn: forældrenes vielse, note og narrativ er væk; familien og begge forældres medlemskaber består.
DO $t$
BEGIN
  PERFORM pg_temp.gdpr_assert(NOT EXISTS (SELECT 1 FROM pg_temp.gdpr_indhold(pg_temp.gid('fam_b')))
    AND NOT EXISTS (SELECT 1 FROM public.fact WHERE id=pg_temp.gid('vielse_b')),'gdpr_barn_familieindhold_slettet');
END $t$;
\echo OK gdpr_barn_familieindhold_slettet
DO $t$
BEGIN
  PERFORM pg_temp.gdpr_assert(EXISTS (SELECT 1 FROM public.family WHERE id=pg_temp.gid('fam_b'))
    AND (SELECT count(*) FROM public.family_member WHERE family_id=pg_temp.gid('fam_b') AND rolle='partner'
      AND person_id IN (pg_temp.gid('f1'),pg_temp.gid('f2')))=2
    AND NOT EXISTS (SELECT 1 FROM public.family_member WHERE person_id=pg_temp.gid('B')),'gdpr_barn_familie_bevaret');
END $t$;
\echo OK gdpr_barn_familie_bevaret
-- Projektejeren 2026-11-20: familiefotoet direkte på den bevarede fam_b består med kobling og historik, men er låst;
-- vielsesfotoet, kun koblet til den slettede vielse, er slettet helt (række, kobling, historik) og stien står i udbakken.
DO $t$
DECLARE v_m bigint:=pg_temp.gid('m_famfoto'); v_rel bigint:=pg_temp.gid('rel_m_famfoto');
BEGIN
  PERFORM pg_temp.gdpr_assert(EXISTS (SELECT 1 FROM public.relation WHERE id=v_rel AND subjekt_type='media' AND subjekt_id=v_m
      AND objekt_type='family' AND objekt_id=pg_temp.gid('fam_b'))
    AND EXISTS (SELECT 1 FROM public.media WHERE id=v_m AND NOT maa_publiceres AND upload_status='klar')
    AND EXISTS (SELECT 1 FROM public.change_event WHERE tabel='relation' AND row_pk->>'id'=v_rel::text AND op='INSERT')
    AND public.family_offentlig(pg_temp.gid('fam_b')) AND NOT public.media_synlig_anon(v_m),'gdpr_barn_familiefoto_kobling_bevaret_laast');
END $t$;
\echo OK gdpr_barn_familiefoto_kobling_bevaret_laast
-- Sikkerhedsfund: på den bevarede kobling står evidenskæden (med historik), mens note og forslag (fritekst) er væk med
-- historik og sæt.
DO $t$
BEGIN
  PERFORM pg_temp.gdpr_assert(EXISTS (SELECT 1 FROM public.assertion WHERE id=pg_temp.gid('kob_assertion'))
    AND EXISTS (SELECT 1 FROM public.conclusion WHERE id=pg_temp.gid('kob_conclusion'))
    AND EXISTS (SELECT 1 FROM public.citation WHERE id=pg_temp.gid('kob_citation'))
    AND EXISTS (SELECT 1 FROM public.change_set WHERE id=pg_temp.gid('kob_saet'))
    AND (SELECT count(*) FROM public.change_event WHERE change_set_id=pg_temp.gid('kob_saet')
      AND tabel IN ('assertion','conclusion','citation'))=3,'gdpr_barn_kobling_evidens_bevaret');
  PERFORM pg_temp.gdpr_assert(NOT EXISTS (SELECT 1 FROM public.note WHERE id=pg_temp.gid('kob_note'))
    AND NOT EXISTS (SELECT 1 FROM public.suggestion WHERE id=pg_temp.gid('kob_forslag'))
    AND NOT EXISTS (SELECT 1 FROM public.change_event WHERE tabel='note' AND row_pk->>'id'=pg_temp.gid('kob_note')::text)
    AND NOT EXISTS (SELECT 1 FROM public.change_set WHERE id=pg_temp.gid('kob_note_saet')),'gdpr_barn_kobling_note_forslag_slettet');
END $t$;
\echo OK gdpr_barn_kobling_evidens_bevaret
\echo OK gdpr_barn_kobling_note_forslag_slettet
-- Gæst (anon, uden redaktør-claim): hverken den bevarede kobling eller billedet kan læses.
BEGIN;
DO $t$
DECLARE v_m bigint:=pg_temp.gid('m_famfoto'); v_rel bigint:=pg_temp.gid('rel_m_famfoto'); v_n int;
  v_a bigint:=pg_temp.gid('kob_assertion'); v_c bigint:=pg_temp.gid('kob_conclusion'); v_ci bigint:=pg_temp.gid('kob_citation');
BEGIN
  PERFORM set_config('request.jwt.claim.sub','',true);
  SET LOCAL ROLE anon;
  SELECT (SELECT count(*) FROM public.relation WHERE id=v_rel)+(SELECT count(*) FROM public.media WHERE id=v_m)
    +(SELECT count(*) FROM public.assertion WHERE id=v_a)+(SELECT count(*) FROM public.conclusion WHERE id=v_c)
    +(SELECT count(*) FROM public.citation WHERE id=v_ci) INTO v_n;
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub','a2a00000-0000-4000-8000-00000000a001',true);
  PERFORM pg_temp.gdpr_assert(v_n=0,'gdpr_barn_familiefoto_anon_skjult');
END $t$;
COMMIT;
\echo OK gdpr_barn_familiefoto_anon_skjult
DO $t$
DECLARE v_m bigint:=pg_temp.gid('m_vielse'); v_rel bigint:=pg_temp.gid('rel_m_vielse');
BEGIN
  PERFORM pg_temp.gdpr_assert(NOT EXISTS (SELECT 1 FROM public.media WHERE id=v_m)
    AND NOT EXISTS (SELECT 1 FROM public.media_variant WHERE media_id=v_m)
    AND NOT EXISTS (SELECT 1 FROM public.relation WHERE id=v_rel OR (subjekt_type='media' AND subjekt_id=v_m))
    AND NOT EXISTS (SELECT 1 FROM public.change_event WHERE (tabel='media' AND row_pk->>'id'=v_m::text)
      OR (tabel='relation' AND row_pk->>'id'=v_rel::text))
    AND EXISTS (SELECT 1 FROM private.person_purge_udbakke WHERE bucket='media' AND sti='gdpr-test/vielse.jpg'),
    'gdpr_barn_vielsesfoto_slettet');
END $t$;
\echo OK gdpr_barn_vielsesfoto_slettet
-- Ingen spor: ingen ny historik (låsen skriver intet), ingen historik om det slettede familieindhold, og den
-- fortrudte vielse med L's navn er væk fra historikken (Codex-fund).
DO $t$
BEGIN
  PERFORM pg_temp.gdpr_assert(NOT EXISTS (
    (SELECT 'change_set',id FROM public.change_set UNION ALL SELECT 'change_event',id FROM public.change_event)
    EXCEPT SELECT * FROM gdpr_history),'gdpr_levende_ingen_ny_historik');
END $t$;
\echo OK gdpr_levende_ingen_ny_historik
DO $t$
BEGIN
  PERFORM pg_temp.gdpr_assert(NOT EXISTS (SELECT 1 FROM public.change_event e JOIN gdpr_indhold_foer v
    ON v.fam IN ('fam_l','fam_b') AND e.tabel=v.tabel AND e.row_pk->>'id'=v.id::text),'gdpr_familieindhold_historik_slettet');
END $t$;
\echo OK gdpr_familieindhold_historik_slettet
DO $t$
BEGIN
  PERFORM pg_temp.gdpr_assert(NOT EXISTS (SELECT 1 FROM gdpr_hist_gl h WHERE
      (h.tabel='change_set' AND EXISTS (SELECT 1 FROM public.change_set WHERE id=h.id))
      OR (h.tabel='change_event' AND EXISTS (SELECT 1 FROM public.change_event WHERE id=h.id)))
    AND NOT EXISTS (SELECT 1 FROM public.change_event e
      WHERE position('Testperson Gdpr Levende' IN coalesce(e.foer::text,''))>0
         OR position('Testperson Gdpr Levende' IN coalesce(e.efter::text,''))>0),'gdpr_fortrudt_vielse_historik_slettet');
END $t$;
\echo OK gdpr_fortrudt_vielse_historik_slettet
-- Codex-fund A: en tidligere familiehændelse (fam_l) og en tidligere person-hændelse (L) efterlader intet: hverken
-- feed-dommen, kaskadesletningen eller sættene.
DO $t$
BEGIN
  PERFORM pg_temp.gdpr_assert((SELECT count(*) FROM gdpr_hist_h WHERE tabel='change_set')=6
    AND NOT EXISTS (SELECT 1 FROM gdpr_hist_h h WHERE
      (h.tabel='change_set' AND EXISTS (SELECT 1 FROM public.change_set WHERE id=h.id))
      OR (h.tabel='change_event' AND EXISTS (SELECT 1 FROM public.change_event WHERE id=h.id)))
    AND NOT EXISTS (SELECT 1 FROM public.change_event WHERE tabel='haendelse'
      AND row_pk->>'id' IN (pg_temp.gid('h_fam')::text,pg_temp.gid('h_pers')::text)),'gdpr_tidligere_haendelse_historik_slettet');
END $t$;
\echo OK gdpr_tidligere_haendelse_historik_slettet
-- Runde 4, punkt C: den levende feed-pin på en tidligere hændelse (fam_l og L) er væk med sin historik.
DO $t$
BEGIN
  PERFORM pg_temp.gdpr_assert(NOT EXISTS (SELECT 1 FROM public.feed_pin
      WHERE kort_noegle IN ('arkiv:'||pg_temp.gid('h_fam'),'arkiv:'||pg_temp.gid('h_pers')))
    AND NOT EXISTS (SELECT 1 FROM public.change_event WHERE tabel='feed_pin'
      AND (efter->>'kort_noegle' IN ('arkiv:'||pg_temp.gid('h_fam'),'arkiv:'||pg_temp.gid('h_pers'))
        OR foer->>'kort_noegle' IN ('arkiv:'||pg_temp.gid('h_fam'),'arkiv:'||pg_temp.gid('h_pers')))),'gdpr_tidligere_haendelse_feed_pin_slettet');
END $t$;
\echo OK gdpr_tidligere_haendelse_feed_pin_slettet
-- Codex runde 4: i det blandede sæt slettes kun L's hændelses event; D's (andres) event og dermed sættet består.
DO $t$
BEGIN
  PERFORM pg_temp.gdpr_assert(EXISTS (SELECT 1 FROM public.change_set WHERE id=pg_temp.gid('mix_saet'))
    AND EXISTS (SELECT 1 FROM public.change_event WHERE change_set_id=pg_temp.gid('mix_saet') AND tabel='haendelse'
      AND row_pk->>'id'=pg_temp.gid('mix_h_d')::text)
    AND NOT EXISTS (SELECT 1 FROM public.change_event WHERE tabel='haendelse' AND row_pk->>'id'=pg_temp.gid('mix_h_l')::text)
    AND NOT EXISTS (SELECT 1 FROM public.haendelse WHERE id=pg_temp.gid('mix_h_l')),'gdpr_blandet_saet_andres_historik_staar');
END $t$;
\echo OK gdpr_blandet_saet_andres_historik_staar
-- Codex runde 5: modstridende ejerskabsbevis (dom under L og under D) → tvetydig → begge domme, deres sæt og D's pin
-- står. Kontrollen (kun L-/familie-domme) er gdpr_tidligere_haendelse_historik_slettet og _feed_pin_slettet ovenfor.
DO $t$
BEGIN
  PERFORM pg_temp.gdpr_assert(NOT EXISTS (SELECT 1 FROM public.haendelse WHERE id=pg_temp.gid('flyt_h'))
    AND (SELECT count(*) FROM public.change_event WHERE tabel='haendelse' AND row_pk->>'id'=pg_temp.gid('flyt_h')::text
      AND change_set_id IN (pg_temp.gid('flyt_dom_l'),pg_temp.gid('flyt_dom_d')))=2
    AND EXISTS (SELECT 1 FROM public.feed_pin WHERE kort_noegle='arkiv:'||pg_temp.gid('flyt_h'))
    AND EXISTS (SELECT 1 FROM public.change_event WHERE tabel='feed_pin' AND efter->>'kort_noegle'='arkiv:'||pg_temp.gid('flyt_h')),
    'gdpr_modstridende_bevis_staar');
END $t$;
\echo OK gdpr_modstridende_bevis_staar

-- Sletning af den afdøde, offentlige O: uændret adfærd.
BEGIN;
DO $t$
DECLARE v_hash text:=(SELECT j->>'sha256' FROM gdpr_preview WHERE hvem='O'); v_id bigint:=pg_temp.gid('O');
BEGIN
  SET LOCAL ROLE authenticated;
  PERFORM public.red_slet_person_helt(v_id,v_hash);
  RESET ROLE;
END $t$;
COMMIT;
DO $t$
BEGIN
  PERFORM pg_temp.gdpr_assert(NOT EXISTS (SELECT 1 FROM public.person WHERE id=pg_temp.gid('O'))
    AND EXISTS (SELECT 1 FROM public.media WHERE id=pg_temp.gid('m_off') AND maa_publiceres)
    AND public.media_synlig_anon(pg_temp.gid('m_off')),'gdpr_offentlig_medie_uaendret');
END $t$;
\echo OK gdpr_offentlig_medie_uaendret
DO $t$
BEGIN
  PERFORM pg_temp.gdpr_assert(NOT EXISTS (SELECT tabel,id FROM gdpr_indhold_foer WHERE fam='fam_o'
      EXCEPT SELECT tabel,id FROM pg_temp.gdpr_indhold(pg_temp.gid('fam_o')))
    AND EXISTS (SELECT 1 FROM public.family WHERE id=pg_temp.gid('fam_o')),'gdpr_offentlig_familieindhold_staar');
END $t$;
\echo OK gdpr_offentlig_familieindhold_staar
-- Runde 4, F: forslag på O's slettede faktum og relation er væk; forslaget på den bevarede familie's vielse står.
DO $t$
BEGIN
  PERFORM pg_temp.gdpr_assert(pg_temp.gid('forslag_o_fakta') IS NOT NULL AND pg_temp.gid('forslag_o_rel') IS NOT NULL
    AND NOT EXISTS (SELECT 1 FROM public.suggestion WHERE id IN (pg_temp.gid('forslag_o_fakta'),pg_temp.gid('forslag_o_rel')))
    AND EXISTS (SELECT 1 FROM public.suggestion WHERE id=pg_temp.gid('forslag_o_vielse'))
    AND (SELECT count(*) FROM jsonb_array_elements((SELECT j FROM gdpr_preview WHERE hvem='O')#>'{steder,S34}') x
      WHERE x->'pk' IN (jsonb_build_object('id',pg_temp.gid('forslag_o_fakta')),jsonb_build_object('id',pg_temp.gid('forslag_o_rel'))))=2,
    'gdpr_offentlig_forslag_paa_slettet_maal_slettet');
END $t$;
\echo OK gdpr_offentlig_forslag_paa_slettet_maal_slettet

-- Forhåndsvisningen viser låste medier, familieindhold der slettes, og vielser der står.
DO $t$
DECLARE l jsonb:=(SELECT j FROM gdpr_preview WHERE hvem='L'); o jsonb:=(SELECT j FROM gdpr_preview WHERE hvem='O');
  p jsonb:=(SELECT j FROM gdpr_preview WHERE hvem='P');
BEGIN
  PERFORM pg_temp.gdpr_assert(l->'blokeringer'='[]'::jsonb AND o->'blokeringer'='[]'::jsonb,'gdpr_preview_ingen_blokering');
  PERFORM pg_temp.gdpr_assert(l->'medier_skjules'=jsonb_build_array(least(pg_temp.gid('m_eget'),pg_temp.gid('m_delt')),
      greatest(pg_temp.gid('m_eget'),pg_temp.gid('m_delt')))
    AND o->'medier_skjules'='[]'::jsonb AND p->'medier_skjules'=jsonb_build_array(purge_test.id('medie_delt')),
    'gdpr_preview_medier_skjules');
END $t$;
\echo OK gdpr_preview_medier_skjules
DO $t$
DECLARE l jsonb:=(SELECT j FROM gdpr_preview WHERE hvem='L'); b jsonb:=(SELECT j FROM gdpr_preview WHERE hvem='B');
BEGIN
  -- Alle kategorier (Codex-fund B): fam_l har også story og relation; historik er et antal.
  PERFORM pg_temp.gdpr_assert(jsonb_array_length(l->'familieindhold_slettes')=1
    AND pg_temp.gdpr_fi(l,pg_temp.gid('fam_l'))-'historik'=jsonb_build_object('family_id',pg_temp.gid('fam_l'),
      'fakta',jsonb_build_array(least(pg_temp.gid('vielse_l'),pg_temp.gid('skilsmisse_l')),greatest(pg_temp.gid('vielse_l'),pg_temp.gid('skilsmisse_l'))),
      'noter',jsonb_build_array(pg_temp.gid('note_l')),'narrativer',jsonb_build_array(pg_temp.gid('narr_l')),
      'haendelser','[]'::jsonb,'stories',jsonb_build_array(pg_temp.gid('story_l')),
      'relationer',jsonb_build_array(pg_temp.gid('rel_l')),'forslag','[]'::jsonb)
    AND (pg_temp.gdpr_fi(l,pg_temp.gid('fam_l'))->>'historik')::int>0
    AND NOT l->'vielser_staar' @> to_jsonb(pg_temp.gid('vielse_l'))
    AND l->'familier_bevares' @> to_jsonb(pg_temp.gid('fam_l')),'gdpr_preview_familieindhold_partner');
  -- fam_b: noten og forslaget på den bevarede familiefoto-kobling og vielsesfotoets relation (på vielsen) tæller med;
  -- selve den bevarede kobling gør ikke.
  PERFORM pg_temp.gdpr_assert(jsonb_array_length(b->'familieindhold_slettes')=1
    AND pg_temp.gdpr_fi(b,pg_temp.gid('fam_b'))-'historik'=jsonb_build_object('family_id',pg_temp.gid('fam_b'),
      'fakta',jsonb_build_array(pg_temp.gid('vielse_b')),
      -- runde 4: også note og forslag på relationen til familiens faktum (vielsesfotoets kobling).
      'noter',(SELECT jsonb_agg(x ORDER BY x) FROM unnest(ARRAY[pg_temp.gid('note_b'),pg_temp.gid('kob_note'),pg_temp.gid('vfoto_note')]) x),
      'narrativer',jsonb_build_array(pg_temp.gid('narr_b')),'haendelser','[]'::jsonb,'stories','[]'::jsonb,
      'relationer',jsonb_build_array(pg_temp.gid('rel_m_vielse')),
      'forslag',(SELECT jsonb_agg(x ORDER BY x) FROM unnest(ARRAY[pg_temp.gid('kob_forslag'),pg_temp.gid('vfoto_forslag')]) x))
    AND (pg_temp.gdpr_fi(b,pg_temp.gid('fam_b'))->>'historik')::int>0
    AND b->'vielser_staar'='[]'::jsonb AND b->'familier_bevares' @> to_jsonb(pg_temp.gid('fam_b')),'gdpr_preview_familieindhold_barn');
  -- Familiefotoet skjules (låses), vielsesfotoet slettes med sin storage-sti.
  PERFORM pg_temp.gdpr_assert(b->'medier_skjules'=jsonb_build_array(pg_temp.gid('m_famfoto'))
    AND b->'storage' @> jsonb_build_array(jsonb_build_object('bucket','media','sti','gdpr-test/vielse.jpg'))
    AND NOT b->'storage' @> jsonb_build_array(jsonb_build_object('bucket','media','sti','gdpr-test/familie.jpg'))
    AND EXISTS (SELECT 1 FROM jsonb_array_elements(b#>'{steder,S37}') x WHERE x->>'tabel'='media'
      AND x->'pk'=jsonb_build_object('id',pg_temp.gid('m_vielse')) AND x->>'handling'='slet'),'gdpr_preview_familiefoto_skjules');
  -- Runde 4, E: det låste familiefoto og den bevarede evidens på dets kobling står altid på kontrollisten.
  PERFORM pg_temp.gdpr_assert((SELECT count(*) FROM jsonb_array_elements(b->'til_kontrol') x WHERE x->>'sted'='NY-E'
      AND ((x->>'tabel'='media' AND x->'pk'=jsonb_build_object('id',pg_temp.gid('m_famfoto')) AND x->>'grund'='laast_familiefoto')
        OR (x->>'tabel'='assertion' AND x->'pk'=jsonb_build_object('id',pg_temp.gid('kob_assertion')) AND x->>'grund'='bevaret_evidens')
        OR (x->>'tabel'='citation' AND x->'pk'=jsonb_build_object('id',pg_temp.gid('kob_citation')) AND x->>'grund'='bevaret_evidens')))=3
    AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements(b->'til_kontrol') x WHERE x->>'sted'='NY-E'
      AND x->'pk'=jsonb_build_object('id',pg_temp.gid('m_vielse')))
    AND NOT EXISTS (SELECT 1 FROM jsonb_array_elements((SELECT j FROM gdpr_preview WHERE hvem='O')->'til_kontrol') x
      WHERE x->>'sted'='NY-E'),'gdpr_preview_kontrol_familiefoto');
END $t$;
\echo OK gdpr_preview_familieindhold_partner
\echo OK gdpr_preview_familieindhold_barn
\echo OK gdpr_preview_familiefoto_skjules
\echo OK gdpr_preview_kontrol_familiefoto
-- Codex-fund B: en bevaret familie med KUN en story, KUN en relation eller KUN historik vises også; runde 4: også kun
-- historik fra en tidligere note på en bevaret familiefoto-kobling (fam_qk).
DO $t$
DECLARE q jsonb:=(SELECT j FROM gdpr_preview WHERE hvem='Q');
  v_tom jsonb:=jsonb_build_object('fakta','[]'::jsonb,'noter','[]'::jsonb,'narrativer','[]'::jsonb,'haendelser','[]'::jsonb,
    'stories','[]'::jsonb,'relationer','[]'::jsonb,'forslag','[]'::jsonb);
BEGIN
  PERFORM pg_temp.gdpr_assert(q->'blokeringer'='[]'::jsonb AND jsonb_array_length(q->'familieindhold_slettes')=4
    AND q->'familier_slettes'='[]'::jsonb,'gdpr_preview_kun_story_relation_historik');
  PERFORM pg_temp.gdpr_assert(pg_temp.gdpr_fi(q,pg_temp.gid('fam_qs'))-'historik'
      =v_tom||jsonb_build_object('family_id',pg_temp.gid('fam_qs'),'stories',jsonb_build_array(pg_temp.gid('story_qs'))),
    'gdpr_preview_kun_story');
  PERFORM pg_temp.gdpr_assert(pg_temp.gdpr_fi(q,pg_temp.gid('fam_qr'))-'historik'
      =v_tom||jsonb_build_object('family_id',pg_temp.gid('fam_qr'),'relationer',jsonb_build_array(pg_temp.gid('rel_qr'))),
    'gdpr_preview_kun_relation');
  PERFORM pg_temp.gdpr_assert(pg_temp.gdpr_fi(q,pg_temp.gid('fam_qh'))-'historik'=v_tom||jsonb_build_object('family_id',pg_temp.gid('fam_qh'))
    AND (pg_temp.gdpr_fi(q,pg_temp.gid('fam_qh'))->>'historik')::int>0,'gdpr_preview_kun_historik');
  PERFORM pg_temp.gdpr_assert(pg_temp.gdpr_fi(q,pg_temp.gid('fam_qk'))=v_tom||jsonb_build_object('family_id',pg_temp.gid('fam_qk'),
      'historik',1) AND q->'medier_skjules' @> to_jsonb(pg_temp.gid('m_qk')),'gdpr_preview_kun_koblingsnote_historik');
END $t$;
\echo OK gdpr_preview_kun_story
\echo OK gdpr_preview_kun_relation
\echo OK gdpr_preview_kun_historik
\echo OK gdpr_preview_kun_koblingsnote_historik
DO $t$
DECLARE o jsonb:=(SELECT j FROM gdpr_preview WHERE hvem='O'); p jsonb:=(SELECT j FROM gdpr_preview WHERE hvem='P');
BEGIN
  PERFORM pg_temp.gdpr_assert(o->'vielser_staar' @> to_jsonb(pg_temp.gid('vielse_o')) AND o->'familieindhold_slettes'='[]'::jsonb
    AND p->'familieindhold_slettes' @> jsonb_build_array(jsonb_build_object('family_id',purge_test.id('fam_keep'),
      'fakta',jsonb_build_array(purge_test.id('fakta_vielse_keep'))))
    AND p->'vielser_staar'='[]'::jsonb,'gdpr_preview_vielse_staar');
  PERFORM pg_temp.gdpr_assert(EXISTS (SELECT 1 FROM jsonb_array_elements((SELECT j FROM gdpr_preview WHERE hvem='L')#>'{steder,NY-E}') s
      WHERE s->>'tabel'='media' AND s->>'handling'='skjul') AND NOT o->'steder' ? 'NY-E','gdpr_preview_sted');
END $t$;
\echo OK gdpr_preview_vielse_staar
\endif
