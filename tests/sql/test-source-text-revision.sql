-- Trin 6a, Task 5: writer-operationen source_text_revision (spec §4.4): ny tekstversion af helposten, forældelse af
-- de afhængige fortolkninger, nyt klausulsæt bundet til versionen, drifttjek over nøgler og bindinger og hele
-- reimport-kæden (authorize → preflight → apply → finalize). Kræver kontrakt v2 (reimport-writer-v2-bootstrap.sql)
-- som klausul-writer-testene. Alt syntetisk; én transaktion, rulles tilbage. Til sidst isolationsvagten i hver sin
-- transaktion (isolationsniveauet sættes ved BEGIN).
\set ON_ERROR_STOP on

-- Sessionens hjælper (oprettes uden for transaktionen, så isolationstestene til sidst også kan bruge den).
CREATE FUNCTION pg_temp.expect_error(p_sql text, p_token text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM IS NULL OR SQLERRM NOT LIKE p_token||'%' THEN
      RAISE EXCEPTION 'TEXT_REVISION_TEST_WRONG_ERROR: expected % got %', p_token, SQLERRM;
    END IF;
    RETURN;
  END;
  RAISE EXCEPTION 'TEXT_REVISION_TEST_NO_ERROR: expected %', p_token;
END $$;

-- Hovedtransaktionen kører eksplicit READ COMMITTED, som writeren kræver (uafhængigt af basens standard).
BEGIN ISOLATION LEVEL READ COMMITTED;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
\ir fixtures/source-text-revision.sql

-- Kør revisionen og forvent en fejl; bagefter må intet være skrevet (ingen tekstversion, intet nyt sæt, ingen
-- forældelse, ingen revisions-event).
CREATE FUNCTION pg_temp.expect_rejected(fx jsonb, p_payload jsonb, p_nonce text, p_token text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_help uuid:=(fx->>'helpost')::uuid;
BEGIN
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.t5_apply(%L::jsonb,%L::jsonb,%L)',fx,p_payload,p_nonce),p_token);
  IF EXISTS (SELECT 1 FROM private.source_observation_text WHERE observation_id=v_help)
     OR (SELECT max(coalesce(clause_set_seq,1)) FROM private.source_observation WHERE parent_observation_id=v_help)<>1
     OR EXISTS (SELECT 1 FROM private.interpretation i JOIN private.interpretation_observation io ON io.interpretation_id=i.id
                  JOIN private.source_observation o ON o.id=io.observation_id
                 WHERE o.parent_observation_id=v_help AND i.status='superseded')
     OR EXISTS (SELECT 1 FROM private.reimport_event WHERE operation='source_text_revision' AND source_record_key=fx->>'record_key') THEN
    RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: afvist revision (%) efterlod skrivninger',p_token;
  END IF;
END $$;

CREATE FUNCTION pg_temp.sha(p text) RETURNS text LANGUAGE sql AS $$ SELECT encode(extensions.digest(p,'sha256'),'hex') $$;

-- test_authorization_forms: operationen er kendt i autorisationens tællinger og elementprefix.
DO $t$
BEGIN
  PERFORM private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"source_text_revision":2}'::jsonb,
    jsonb_build_object('source-text-revision:a','{}'::jsonb,'source-text-revision:b','{}'::jsonb));
  PERFORM private.validate_reimport_authorization_payload(
    '{"person_creates":0,"source_evidence":0,"legacy_migrations":0,"clause_evidence":0,"interpretation_proposals":0,"clause_revisions":0,"relation_personas":0,"relation_person_creates":0,"relation_dispositions":0,"source_text_revision":1}'::jsonb,
    jsonb_build_object('source-text-revision:a','{}'::jsonb));
  PERFORM pg_temp.expect_error($q$SELECT private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"source_text_revision":1}'::jsonb, jsonb_build_object('clause-revision:a','{}'::jsonb))$q$,'REIMPORT_WRITER_AUTHORIZATION_INVALID');
  PERFORM pg_temp.expect_error($q$SELECT private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"clause_revisions":1}'::jsonb, jsonb_build_object('source-text-revision:a','{}'::jsonb))$q$,'REIMPORT_WRITER_AUTHORIZATION_INVALID');
  PERFORM pg_temp.expect_error($q$SELECT private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"source_text_revision":"1"}'::jsonb, jsonb_build_object('source-text-revision:a','{}'::jsonb))$q$,'REIMPORT_WRITER_AUTHORIZATION_INVALID');
  PERFORM pg_temp.expect_error($q$SELECT private.validate_reimport_authorization_payload('{"person_creates":0,"source_evidence":0,"source_text_revisions":1}'::jsonb, jsonb_build_object('source-text-revision:a','{}'::jsonb))$q$,'REIMPORT_WRITER_AUTHORIZATION_INVALID');
  RAISE NOTICE 'OK: test_authorization_forms';
END $t$;

-- test_revision_happy_path + test_revision_narrative_state_unchanged + kvitteringen.
DO $t$
DECLARE v_actor uuid:='11000000-0000-0000-0000-00000006a501'; fx jsonb; e jsonb; p jsonb; r jsonb; v_help uuid; v_occ record;
  v_tv private.source_observation_text%ROWTYPE; v_parties jsonb; v_state_before text; v_state_after text; v_n int; v_ev jsonb;
  v_new text:='Anna Alfa. Gift m. Bo Beta.'; v_cur record; v_h1 text; v_e1 text; v_e2 text;
BEGIN
  fx:=pg_temp.t5_post(-65101,v_actor,true,true);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  v_help:=(fx->>'helpost')::uuid;
  e:=pg_temp.t5_expected(v_help);
  IF jsonb_array_length(e->'keys')<>3 OR jsonb_array_length(e->'bindings')<>2
     OR NOT e->'bindings' @> jsonb_build_array(jsonb_build_object('promotion_id',fx->>'assertion_promotion','target_type','assertion'),
                                               jsonb_build_object('promotion_id',fx->>'family_promotion','target_type','family')) THEN
    RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: fixturens mængder %',e;
  END IF;
  SELECT coalesce(jsonb_agg(to_jsonb(pc) ORDER BY pc.interpretation_key,pc.party_role),'[]') INTO v_parties
    FROM private.interpretation_party_current pc WHERE pc.interpretation_key IN (SELECT (k#>>'{}')::uuid FROM jsonb_array_elements(e->'keys') k);
  IF jsonb_array_length(v_parties)<>2 THEN RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: fixturens parter %',v_parties; END IF;
  v_state_before:=private.reimport_canonical_json_sha256(private.narrative_publication_state((fx->>'person')::bigint,(fx->>'source')::bigint,fx->>'record_key'));
  IF private.narrative_publication_state((fx->>'person')::bigint,(fx->>'source')::bigint,fx->>'record_key')->>'publication_status'<>'published' THEN
    RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: fixturens narrativ er ikke publiceret';
  END IF;
  v_h1:=private.clause_set_sha256(v_help,1);

  p:=pg_temp.t5_payload(fx,v_new,ARRAY['Anna Alfa.','Gift m. Bo Beta.']);
  r:=pg_temp.t5_apply(fx,p,'happy');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;

  -- én tekstversion: samme spænd og rendition som helposten, foretrukken, med proveniens
  SELECT count(*) INTO v_n FROM private.source_observation_text WHERE observation_id=v_help;
  IF v_n<>1 THEN RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: % tekstversioner',v_n; END IF;
  SELECT * INTO v_tv FROM private.source_observation_text WHERE observation_id=v_help;
  SELECT o.rendition_id,ob.char_from,ob.char_to INTO v_occ FROM private.source_observation ob
    JOIN private.source_record_occurrence o ON o.id=ob.occurrence_id WHERE ob.id=v_help;
  IF v_tv.id<>(r->>'text_id')::uuid OR v_tv.version<>1 OR v_tv.supersedes_id IS NOT NULL OR NOT v_tv.is_preferred
     OR v_tv.rendition_id<>v_occ.rendition_id OR v_tv.char_from<>v_occ.char_from OR v_tv.char_to<>v_occ.char_to
     OR v_tv.verbatim_text<>v_new OR v_tv.created_by<>v_actor
     OR v_tv.extraction_run_id IS DISTINCT FROM (r->>'run_id')::uuid OR v_tv.method<>'folded_projection@page_header'
     OR v_tv.evidence->>'batch_id'<>r->>'batch_id' OR v_tv.evidence->>'element_id'<>'source-text-revision:'||(fx->>'record_key')
     OR v_tv.evidence->>'profile_id'<>'t5-source-text-revision' OR v_tv.evidence->>'before_text_sha256'<>pg_temp.sha(fx->>'text')
     OR v_tv.evidence->>'manifest_sha256' IS NULL THEN
    RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: tekstversion %',to_jsonb(v_tv);
  END IF;
  -- helpost_text_current returnerer den nye tekst
  SELECT * INTO v_cur FROM private.helpost_text_current(v_help);
  IF v_cur.text_id IS DISTINCT FROM v_tv.id OR v_cur.verbatim_text<>v_new THEN
    RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: helpost_text_current %',to_jsonb(v_cur);
  END IF;
  -- nyt sæt seq+1 bundet til versionen; det gamle sæt erstattet
  IF (SELECT count(*) FROM private.source_observation WHERE parent_observation_id=v_help AND clause_set_seq=2 AND parent_text_id=v_tv.id)<>2
     OR EXISTS (SELECT 1 FROM private.source_observation WHERE parent_observation_id=v_help AND clause_set_seq=2 AND parent_text_id IS DISTINCT FROM v_tv.id)
     OR (SELECT count(*) FROM private.clause_observation_current WHERE parent_observation_id=v_help)<>2
     OR (r->>'clause_set_seq')::int<>2 THEN
    RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: nyt sæt';
  END IF;
  IF EXISTS (SELECT 1 FROM private.source_observation o LEFT JOIN private.clause_disposition_current d ON d.observation_id=o.id
              WHERE o.parent_observation_id=v_help AND coalesce(o.clause_set_seq,1)=1 AND d.disposition IS DISTINCT FROM 'erstattet') THEN
    RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: gamle klausuler ikke erstattet';
  END IF;
  IF r->>'before_clause_set_sha256'<>v_h1 OR r->>'after_clause_set_sha256'<>private.clause_set_sha256(v_help,2) THEN
    RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: sæt-hashes %',r;
  END IF;
  -- nøglerne forældet med grundlaget source_text_revision
  IF (SELECT count(*) FROM private.interpretation_current ic
       WHERE ic.interpretation_key IN (SELECT (k#>>'{}')::uuid FROM jsonb_array_elements(e->'keys') k)
         AND ic.status='superseded' AND ic.decision_evidence->>'basis'='source_text_revision'
         AND ic.decision_evidence->>'text_id_after'=v_tv.id::text AND ic.decided_by=v_actor)<>3 THEN
    RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: forældelse';
  END IF;
  IF private.assertion_binding_current((fx->>'assertion_promotion')::uuid) THEN
    RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: assertion-bindingen er stadig gældende';
  END IF;
  -- kvitteringen
  IF r->'superseded_keys'<>e->'keys' THEN RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: superseded_keys %',r->'superseded_keys'; END IF;
  IF (SELECT jsonb_agg(jsonb_build_object('promotion_id',b->>'promotion_id','target_type',b->>'target_type') ORDER BY b->>'promotion_id')
        FROM jsonb_array_elements(r->'binding_loss') b)<>e->'bindings'
     OR NOT r->'binding_loss' @> jsonb_build_array(
          jsonb_build_object('promotion_id',fx->>'assertion_promotion','target_type','assertion','interpretation_key',fx->>'death_key','target_id',fx->>'assertion'),
          jsonb_build_object('promotion_id',fx->>'family_promotion','target_type','family','interpretation_key',fx->>'marriage_key','target_id',fx->>'family')) THEN
    RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: binding_loss %',r->'binding_loss';
  END IF;
  IF r->'parties_dropped'<>v_parties THEN RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: parties_dropped %',r->'parties_dropped'; END IF;
  IF r->'personas_on_old_set'<>jsonb_build_array(fx->>'spouse_persona') THEN
    RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: personas_on_old_set %',r->'personas_on_old_set';
  END IF;
  IF r->>'text_id'<>v_tv.id::text OR (r->>'text_version')::int<>1 THEN RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: text_id %',r; END IF;
  -- eventet bærer kvitteringen
  SELECT payload INTO v_ev FROM private.reimport_event WHERE batch_id=(r->>'batch_id')::uuid AND operation='source_text_revision'
     AND element_id='source-text-revision:'||(fx->>'record_key') AND source_record_key=fx->>'record_key'
     AND before_sha256=pg_temp.sha(fx->>'text') AND after_sha256=pg_temp.sha(v_new);
  IF v_ev IS NULL OR v_ev->'superseded_keys'<>r->'superseded_keys' OR v_ev->'binding_loss'<>r->'binding_loss'
     OR v_ev->>'text_id'<>r->>'text_id' OR v_ev->'parties_dropped'<>r->'parties_dropped'
     OR v_ev->'personas_on_old_set'<>r->'personas_on_old_set' OR v_ev->>'clause_set_seq'<>'2'
     OR v_ev->>'before_clause_set_sha256'<>v_h1 OR v_ev->>'after_clause_set_sha256'<>r->>'after_clause_set_sha256'
     OR v_ev->'expected_binding_loss'<>p->'expected_binding_loss' THEN
    RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: event %',v_ev;
  END IF;
  -- eventet gemmer ikke postteksten: payload minus verbatim_text plus kvitteringen
  IF v_ev ? 'verbatim_text' OR v_ev->>'after_text_sha256'<>pg_temp.sha(v_new)
     OR v_ev<>(p-'verbatim_text')||(r-'batch_id'-'authorization_id'-'preflight'-'finalize'-'second_apply_error') THEN
    RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: event bærer posttekst eller afviger fra payload+kvittering';
  END IF;
  -- fortolkningernes link-krav står udskudt igen efter writeren: en fortolkning uden link kan indsættes og fejler
  -- først, når kravet gøres IMMEDIATE (alt rulles tilbage i en undertransaktion).
  BEGIN
    INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,predicate,
      value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
    SELECT gen_random_uuid(),gen_random_uuid(),1,(fx->>'source')::bigint,NULL,'relation','relation.marriage','{"raw":"x","normalized":"x"}',
      'fixture','model_inference',0.5,'proposed','fixture',(fx->'src'->>'run')::uuid;
    BEGIN
      SET CONSTRAINTS private.interpretation_has_observation IMMEDIATE;
      v_e1:='ingen fejl';
    EXCEPTION WHEN OTHERS THEN v_e1:=SQLERRM;
    END;
    RAISE EXCEPTION 'T5_ROLLBACK_MARK';
  EXCEPTION WHEN OTHERS THEN v_e2:=SQLERRM;
  END;
  SET CONSTRAINTS ALL DEFERRED;
  IF v_e2<>'T5_ROLLBACK_MARK' OR v_e1='ingen fejl' THEN
    RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: link-kravet efter writeren (indsæt: %, immediate: %)',v_e2,v_e1;
  END IF;
  -- narrativets publiceringstilstand er uændret
  v_state_after:=private.reimport_canonical_json_sha256(private.narrative_publication_state((fx->>'person')::bigint,(fx->>'source')::bigint,fx->>'record_key'));
  IF v_state_after<>v_state_before THEN RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: narrativ-tilstand ændret'; END IF;
  -- intet afhænger længere af det aktuelle sæt
  IF (SELECT count(*) FROM private.text_revision_dependents(v_help))<>0 THEN
    RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: afhængigheder efter revisionen';
  END IF;
  RAISE NOTICE 'OK: test_revision_happy_path, test_revision_narrative_state_unchanged';

  -- test_revision_second_version: B → C på samme post giver version 2, der afløser version 1.
  p:=pg_temp.t5_payload(fx,'Anna Alfa. Gift m. Bo B.',ARRAY['Anna Alfa.','Gift m. Bo B.']);
  IF p->'expected_superseded_keys'<>'[]'::jsonb OR p->'expected_binding_loss'<>'[]'::jsonb
     OR p->>'before_text_sha256'<>pg_temp.sha(v_new) OR (p->>'replaces_clause_set_seq')::int<>2 THEN
    RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: anden payload %',p;
  END IF;
  r:=pg_temp.t5_apply(fx,p,'second');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  SELECT * INTO v_cur FROM private.helpost_text_current(v_help);
  IF v_cur.text_id IS DISTINCT FROM (r->>'text_id')::uuid OR v_cur.verbatim_text<>'Anna Alfa. Gift m. Bo B.'
     OR (r->>'text_version')::int<>2 OR (r->>'clause_set_seq')::int<>3
     OR NOT EXISTS (SELECT 1 FROM private.source_observation_text WHERE id=(r->>'text_id')::uuid AND version=2 AND supersedes_id=v_tv.id AND is_preferred)
     OR (SELECT count(*) FROM private.source_observation WHERE parent_observation_id=v_help AND clause_set_seq=3 AND parent_text_id=(r->>'text_id')::uuid)<>2
     OR r->'superseded_keys'<>'[]'::jsonb OR r->'binding_loss'<>'[]'::jsonb THEN
    RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: anden version %',r;
  END IF;
  RAISE NOTICE 'OK: test_revision_second_version';
END $t$;

-- test_revision_binding_drift_assertion og test_revision_binding_drift_family: én manglende eller ekstra binding i den
-- forventede mængde ⇒ TEXT_REVISION_BINDING_SET_DRIFT, og intet er skrevet.
DO $t$
DECLARE v_actor uuid:='11000000-0000-0000-0000-00000006a502'; fx jsonb; e jsonb; p jsonb; v_extra jsonb;
BEGIN
  fx:=pg_temp.t5_post(-65201,v_actor,false,true);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  e:=pg_temp.t5_expected((fx->>'helpost')::uuid);
  -- assertion-bindingen mangler
  p:=pg_temp.t5_payload(fx,'Anna Alfa. Gift m. Bo Beta.',ARRAY['Anna Alfa.','Gift m. Bo Beta.'],
    jsonb_build_object('keys',e->'keys','bindings',(SELECT jsonb_agg(b ORDER BY b->>'promotion_id') FROM jsonb_array_elements(e->'bindings') b WHERE b->>'target_type'<>'assertion')));
  PERFORM pg_temp.expect_rejected(fx,p,'drift-a1','TEXT_REVISION_BINDING_SET_DRIFT');
  -- en ekstra (ukendt) assertion-binding
  v_extra:=jsonb_build_object('promotion_id','ffffffff-ffff-4fff-8fff-ffffffffffff','target_type','assertion');
  p:=pg_temp.t5_payload(fx,'Anna Alfa. Gift m. Bo Beta.',ARRAY['Anna Alfa.','Gift m. Bo Beta.'],
    jsonb_build_object('keys',e->'keys','bindings',(SELECT jsonb_agg(b ORDER BY b->>'promotion_id') FROM jsonb_array_elements(e->'bindings'||v_extra) b)));
  PERFORM pg_temp.expect_rejected(fx,p,'drift-a2','TEXT_REVISION_BINDING_SET_DRIFT');
  -- rigtig promotion, forkert måltype
  p:=pg_temp.t5_payload(fx,'Anna Alfa. Gift m. Bo Beta.',ARRAY['Anna Alfa.','Gift m. Bo Beta.'],
    jsonb_build_object('keys',e->'keys','bindings',(SELECT jsonb_agg(CASE WHEN b->>'target_type'='assertion' THEN jsonb_set(b,'{target_type}','"family"') ELSE b END ORDER BY b->>'promotion_id') FROM jsonb_array_elements(e->'bindings') b)));
  PERFORM pg_temp.expect_rejected(fx,p,'drift-a3','TEXT_REVISION_BINDING_SET_DRIFT');
  RAISE NOTICE 'OK: test_revision_binding_drift_assertion';
  -- familiebindingen mangler
  p:=pg_temp.t5_payload(fx,'Anna Alfa. Gift m. Bo Beta.',ARRAY['Anna Alfa.','Gift m. Bo Beta.'],
    jsonb_build_object('keys',e->'keys','bindings',(SELECT jsonb_agg(b ORDER BY b->>'promotion_id') FROM jsonb_array_elements(e->'bindings') b WHERE b->>'target_type'<>'family')));
  PERFORM pg_temp.expect_rejected(fx,p,'drift-f1','TEXT_REVISION_BINDING_SET_DRIFT');
  -- en ekstra familiebinding
  v_extra:=jsonb_build_object('promotion_id','00000000-0000-4000-8000-000000000001','target_type','family');
  p:=pg_temp.t5_payload(fx,'Anna Alfa. Gift m. Bo Beta.',ARRAY['Anna Alfa.','Gift m. Bo Beta.'],
    jsonb_build_object('keys',e->'keys','bindings',(SELECT jsonb_agg(b ORDER BY b->>'promotion_id') FROM jsonb_array_elements(e->'bindings'||v_extra) b)));
  PERFORM pg_temp.expect_rejected(fx,p,'drift-f2','TEXT_REVISION_BINDING_SET_DRIFT');
  RAISE NOTICE 'OK: test_revision_binding_drift_family';

  -- test_revision_key_drift: en manglende eller en ekstra nøgle ⇒ TEXT_REVISION_KEY_SET_DRIFT.
  p:=pg_temp.t5_payload(fx,'Anna Alfa. Gift m. Bo Beta.',ARRAY['Anna Alfa.','Gift m. Bo Beta.'],
    jsonb_build_object('keys',(SELECT jsonb_agg(k ORDER BY k#>>'{}') FROM jsonb_array_elements(e->'keys') k WHERE k#>>'{}'<>fx->>'proposed_key'),'bindings',e->'bindings'));
  PERFORM pg_temp.expect_rejected(fx,p,'drift-k1','TEXT_REVISION_KEY_SET_DRIFT');
  p:=pg_temp.t5_payload(fx,'Anna Alfa. Gift m. Bo Beta.',ARRAY['Anna Alfa.','Gift m. Bo Beta.'],
    jsonb_build_object('keys',(SELECT jsonb_agg(k ORDER BY k#>>'{}') FROM jsonb_array_elements(e->'keys'||'["00000000-0000-4000-8000-0000000000aa"]'::jsonb) k),'bindings',e->'bindings'));
  PERFORM pg_temp.expect_rejected(fx,p,'drift-k2','TEXT_REVISION_KEY_SET_DRIFT');
  RAISE NOTICE 'OK: test_revision_key_drift';

  -- test_revision_noop: samme tekst ⇒ TEXT_REVISION_NOOP.
  p:=pg_temp.t5_payload(fx,fx->>'text',ARRAY['Anna Alfa.','Gift med Bo Beta.']);
  PERFORM pg_temp.expect_rejected(fx,p,'noop','TEXT_REVISION_NOOP');
  RAISE NOTICE 'OK: test_revision_noop';

  -- test_revision_base_drift: forkert before_text_sha256, forkert sæt-hash eller forkert sæt-nummer.
  p:=pg_temp.t5_payload(fx,'Anna Alfa. Gift m. Bo Beta.',ARRAY['Anna Alfa.','Gift m. Bo Beta.']);
  PERFORM pg_temp.expect_rejected(fx,jsonb_set(p,'{before_text_sha256}',to_jsonb(repeat('0',64))),'base-1','TEXT_REVISION_BASE_DRIFT');
  PERFORM pg_temp.expect_rejected(fx,jsonb_set(p,'{replaces_clause_set_sha256}',to_jsonb(repeat('0',64))),'base-2','TEXT_REVISION_BASE_DRIFT');
  PERFORM pg_temp.expect_rejected(fx,jsonb_set(p,'{replaces_clause_set_seq}','2'),'base-3','TEXT_REVISION_BASE_DRIFT');
  RAISE NOTICE 'OK: test_revision_base_drift';

  -- test_revision_span_mismatch: payloaden bærer intet spænd; en anden renditions hash ⇒ TEXT_REVISION_SPAN_MISMATCH.
  PERFORM pg_temp.expect_rejected(fx,jsonb_set(p,'{rendition_content_sha256}',to_jsonb(repeat('9',64))),'span-1','TEXT_REVISION_SPAN_MISMATCH');
  RAISE NOTICE 'OK: test_revision_span_mismatch';

  -- Payloadform: lukket nøglesæt, intern konsistens, sorterede mængder, profilens tekstform.
  PERFORM pg_temp.expect_rejected(fx,p||'{"source_span":{"char_from":0,"char_to":1}}','inv-1','REIMPORT_WRITER_SOURCE_TEXT_REVISION_INVALID');
  PERFORM pg_temp.expect_rejected(fx,p-'expected_binding_loss','inv-2','REIMPORT_WRITER_SOURCE_TEXT_REVISION_INVALID');
  PERFORM pg_temp.expect_rejected(fx,jsonb_set(p,'{after_text_sha256}',to_jsonb(repeat('a',64))),'inv-3','REIMPORT_WRITER_SOURCE_TEXT_REVISION_INVALID');
  PERFORM pg_temp.expect_rejected(fx,jsonb_set(p,'{projection_rule}','"folded_projection@anywhere"'),'inv-4','REIMPORT_WRITER_SOURCE_TEXT_REVISION_INVALID');
  PERFORM pg_temp.expect_rejected(fx,jsonb_set(p,'{expected_superseded_keys}',(SELECT jsonb_agg(k ORDER BY k#>>'{}' DESC) FROM jsonb_array_elements(e->'keys') k)),'inv-5','REIMPORT_WRITER_SOURCE_TEXT_REVISION_INVALID');
  PERFORM pg_temp.expect_rejected(fx,jsonb_set(p,'{expected_superseded_keys}',e->'keys'||jsonb_build_array(e->'keys'->0)),'inv-6','REIMPORT_WRITER_SOURCE_TEXT_REVISION_INVALID');
  PERFORM pg_temp.expect_rejected(fx,jsonb_set(p,'{expected_binding_loss}',jsonb_build_array(jsonb_build_object('promotion_id',fx->>'family_promotion','target_type','family','target_id','1'))),'inv-7','REIMPORT_WRITER_SOURCE_TEXT_REVISION_INVALID');
  PERFORM pg_temp.expect_rejected(fx,jsonb_set(p,'{expected_superseded_keys}','["ikke-en-uuid"]'),'inv-8','REIMPORT_WRITER_SOURCE_TEXT_REVISION_INVALID');
  RAISE NOTICE 'OK: payloadform';

  -- Til sidst virker den rigtige payload på samme fixture (afvisningerne efterlod intet).
  PERFORM pg_temp.t5_apply(fx,p,'drift-ok');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  RAISE NOTICE 'OK: korrekt payload efter afvisningerne';
END $t$;

-- test_revision_multi_set_post: sæt 1 er erstattet (en nøgle citerer kun det), sæt 2 er aktuelt. Kun sæt 2-nøgler
-- forældes, og det nye sæt er 3.
DO $t$
DECLARE v_actor uuid:='11000000-0000-0000-0000-00000006a503'; s jsonb; post jsonb; k_old uuid; k_new uuid; v_c2 uuid; fx jsonb;
  p jsonb; r jsonb; v_text text:='Anna Alfa. Gift med Bo Beta.';
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  s:=pg_temp.f5b_source(-65301);
  post:=pg_temp.f5b_post(-65301,s,'T5-MS',v_text,ARRAY['Anna Alfa.','Gift med Bo Beta.'],NULL,v_actor);
  k_old:=(pg_temp.f5b_claim(-65301,s,'relation.marriage',(post->'clauses'->>1)::uuid,'Gift med Bo Beta.')->>'key')::uuid;
  INSERT INTO private.source_observation(occurrence_id,observation_kind,page_from,page_to,char_from,char_to,verbatim_text,
    quality_status,extraction_method,extraction_run_id,parent_observation_id,post_char_from,post_char_to,clause_ordinal,
    clause_classification,clause_flags,clause_set_seq)
  VALUES ((post->>'occ')::uuid,'clause',10,10,1000,1028,v_text,'clear','clause_segment_v1',
    (s->>'run')::uuid,(post->>'helpost')::uuid,0,28,1,'record_text','[]',2) RETURNING id INTO v_c2;
  INSERT INTO private.clause_disposition(observation_id,version,disposition,decided_by_kind,evidence)
  SELECT o.id,1,'erstattet','machine',jsonb_build_object('manifest_sha256',repeat('a',64),'extraction_run_id',s->>'run')
    FROM private.source_observation o WHERE o.parent_observation_id=(post->>'helpost')::uuid AND o.clause_set_seq=1;
  k_new:=(pg_temp.f5b_claim(-65301,s,'relation.marriage',v_c2,v_text)->>'key')::uuid;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  fx:=jsonb_build_object('source',-65301,'record_key','T5-MS','helpost',post->>'helpost','text',v_text,'actor',v_actor,
    'profile',pg_temp.t5_profile(-65301));
  p:=pg_temp.t5_payload(fx,'Anna Alfa. Gift m. Bo Beta.',ARRAY['Anna Alfa.','Gift m. Bo Beta.']);
  IF p->'expected_superseded_keys'<>jsonb_build_array(k_new::text) OR (p->>'replaces_clause_set_seq')::int<>2 THEN
    RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: multi-sæt payload %',p;
  END IF;
  r:=pg_temp.t5_apply(fx,p,'multi');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF (SELECT status FROM private.interpretation_current WHERE interpretation_key=k_new)<>'superseded'
     OR (SELECT status FROM private.interpretation_current WHERE interpretation_key=k_old)<>'proposed'
     OR (r->>'clause_set_seq')::int<>3 OR r->'superseded_keys'<>jsonb_build_array(k_new::text)
     OR (SELECT disposition FROM private.clause_disposition_current WHERE observation_id=v_c2)<>'erstattet' THEN
    RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: multi-sæt %',r;
  END IF;
  RAISE NOTICE 'OK: test_revision_multi_set_post';
END $t$;

-- test_revision_full_chain: authorize → preflight → apply → finalize; en anden apply af samme element afvises, og
-- finalize-tællingen stemmer. Batch-resultatet kender operationen.
DO $t$
DECLARE v_actor uuid:='11000000-0000-0000-0000-00000006a504'; fx jsonb; r jsonb; v_res jsonb; v_err text;
BEGIN
  fx:=pg_temp.t5_post(-65401,v_actor,false,false);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  r:=pg_temp.t5_apply(fx,pg_temp.t5_payload(fx,'Anna Alfa. Gift m. Bo Beta.',ARRAY['Anna Alfa.','Gift m. Bo Beta.']),'chain',true);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF r->'preflight'->>'authorization_id'<>r->>'authorization_id' THEN RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: preflight %',r->'preflight'; END IF;
  IF r->>'second_apply_error' NOT LIKE 'REIMPORT_WRITER_SOURCE_TEXT_REVISION_EXISTS%' THEN
    RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: anden apply gav %',r->>'second_apply_error';
  END IF;
  IF r->'finalize'->'counts'<>'{"person_creates":0,"source_evidence":0,"source_text_revision":1}'::jsonb
     OR (SELECT observed_counts FROM private.reimport_batch WHERE id=(r->>'batch_id')::uuid)<>'{"person_creates":0,"source_evidence":0,"source_text_revision":1}'::jsonb
     OR (SELECT count(*) FROM private.reimport_event WHERE batch_id=(r->>'batch_id')::uuid)<>1 THEN
    RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: finalize %',r->'finalize';
  END IF;
  -- binding_loss: kun familien (dødsfortolkningen er accepteret, men ikke bundet)
  IF jsonb_array_length(r->'binding_loss')<>1 OR r->'binding_loss'->0->>'target_type'<>'family' THEN
    RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: binding_loss %',r->'binding_loss';
  END IF;
  PERFORM set_config('request.jwt.claim.sub',fx->>'actor',true); PERFORM set_config('role','authenticated',true);
  v_res:=public.red_reimport_batch_result((r->>'authorization_id')::uuid,(r->>'batch_id')::uuid);
  RESET role;
  IF v_res->>'status'<>'finalized' THEN RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: batch-resultat %',v_res; END IF;
  -- efter finalize er batchen lukket for flere apply
  BEGIN
    PERFORM set_config('role','authenticated',true);
    PERFORM public.red_apply_reimport_source_text_revision((r->>'batch_id')::uuid,'source-text-revision:'||(fx->>'record_key'),'{}');
    v_err:='ingen fejl';
  EXCEPTION WHEN OTHERS THEN v_err:=SQLERRM;
  END;
  RESET role;
  IF v_err NOT LIKE 'REIMPORT_WRITER_BATCH_INVALID%' THEN RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: apply efter finalize gav %',v_err; END IF;
  RAISE NOTICE 'OK: test_revision_full_chain';
END $t$;

-- Afhængigheder, revisionen ikke kan bære, afvises gennem writeren: et direkte link til helposten
-- (TEXT_REVISION_DEPENDENCY_UNSUPPORTED fra text_revision_dependents) og en menneskelig klausuldisposition.
DO $t$
DECLARE v_actor uuid:='11000000-0000-0000-0000-00000006a505'; fx jsonb; v_clause uuid; v_key uuid;
BEGIN
  fx:=pg_temp.t5_post(-65501,v_actor,false,false);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
  SELECT ic.id,(fx->>'helpost')::uuid,'context',2 FROM private.interpretation_current ic WHERE ic.interpretation_key=(fx->>'proposed_key')::uuid;
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.t5_payload(%L::jsonb,%L,%L::text[])',fx,'Anna Alfa. Gift m. Bo Beta.',ARRAY['Anna Alfa.','Gift m. Bo Beta.']),
    'TEXT_REVISION_DEPENDENCY_UNSUPPORTED');
  PERFORM pg_temp.expect_rejected(fx,pg_temp.t5_payload(fx,'Anna Alfa. Gift m. Bo Beta.',ARRAY['Anna Alfa.','Gift m. Bo Beta.'],
    '{"keys":[],"bindings":[]}'),'dep-1','TEXT_REVISION_DEPENDENCY_UNSUPPORTED');
  RAISE NOTICE 'OK: direkte helpost-link afvises';

  fx:=pg_temp.t5_post(-65511,v_actor,false,false);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  SELECT id INTO v_clause FROM private.source_observation WHERE parent_observation_id=(fx->>'helpost')::uuid AND clause_ordinal=1;
  INSERT INTO private.clause_disposition(observation_id,version,disposition,decided_by_kind,decided_by,decided_by_name,decided_at,evidence)
  VALUES(v_clause,1,'struktureret','human',v_actor,'Fixture',clock_timestamp(),'{"ark":"fixture"}');
  PERFORM pg_temp.expect_rejected(fx,pg_temp.t5_payload(fx,'Anna Alfa. Gift m. Bo Beta.',ARRAY['Anna Alfa.','Gift m. Bo Beta.']),
    'dep-2','TEXT_REVISION_DEPENDENCY_UNSUPPORTED');
  RAISE NOTICE 'OK: menneskelig disposition afvises';
END $t$;

-- test_revision_span_mismatch_existing_version: en eksisterende tekstversion i et andet spænd eller en anden rendition
-- ⇒ TEXT_REVISION_SPAN_MISMATCH. Versionen bærer basisteksten, så basiskontrollen består og spændkontrollen afgør.
DO $t$
DECLARE v_actor uuid:='11000000-0000-0000-0000-00000006a506'; fx jsonb; v_help uuid; v_rend uuid; v_err text; v_case text;
BEGIN
  FOREACH v_case IN ARRAY ARRAY['span','rendition'] LOOP
    fx:=pg_temp.t5_post(CASE v_case WHEN 'span' THEN -65601 ELSE -65611 END,v_actor,false,false);
    SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
    v_help:=(fx->>'helpost')::uuid;
    IF v_case='span' THEN
      INSERT INTO private.source_observation_text(observation_id,rendition_id,version,verbatim_text,char_from,char_to)
      VALUES (v_help,(fx->'src'->>'rend')::uuid,1,fx->>'text',1001,1000+char_length(fx->>'text'));
    ELSE
      INSERT INTO private.source_rendition(source_id,rendition_key,rendition_kind,content_sha256,metadata)
      VALUES ((fx->>'source')::bigint,'t5-anden','pdf_text_layer',repeat('8',64),'{}') RETURNING id INTO v_rend;
      INSERT INTO private.source_observation_text(observation_id,rendition_id,version,verbatim_text,char_from,char_to)
      VALUES (v_help,v_rend,1,fx->>'text',1000,1000+char_length(fx->>'text'));
    END IF;
    BEGIN
      PERFORM pg_temp.t5_apply(fx,pg_temp.t5_payload(fx,'Anna Alfa. Gift m. Bo Beta.',ARRAY['Anna Alfa.','Gift m. Bo Beta.']),'span-'||v_case);
      v_err:='ingen fejl';
    EXCEPTION WHEN OTHERS THEN v_err:=SQLERRM;
    END;
    IF v_err NOT LIKE 'TEXT_REVISION_SPAN_MISMATCH%'
       OR (SELECT count(*) FROM private.source_observation_text WHERE observation_id=v_help)<>1 THEN
      RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: eksisterende version (%) gav %',v_case,v_err;
    END IF;
  END LOOP;
  RAISE NOTICE 'OK: test_revision_span_mismatch_existing_version';
END $t$;

-- Signatur og rettigheder: clause_write_set har kun 5-argument-formen; RPC'en er authenticated-kaldbar, writeren privat.
DO $t$
DECLARE r text;
BEGIN
  IF to_regprocedure('private.clause_write_set(jsonb,jsonb,integer,text)') IS NOT NULL
     OR to_regprocedure('private.clause_write_set(jsonb,jsonb,integer,text,uuid)') IS NULL
     OR (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace WHERE n.nspname='private' AND p.proname='clause_write_set')<>1 THEN
    RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: clause_write_set-signatur';
  END IF;
  IF NOT has_function_privilege('authenticated','public.red_apply_reimport_source_text_revision(uuid,text,jsonb)','EXECUTE')
     OR has_function_privilege('anon','public.red_apply_reimport_source_text_revision(uuid,text,jsonb)','EXECUTE')
     OR has_function_privilege('service_role','public.red_apply_reimport_source_text_revision(uuid,text,jsonb)','EXECUTE') THEN
    RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: RPC-rettigheder';
  END IF;
  FOREACH r IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    IF has_function_privilege(r,'private.write_source_text_revision(uuid,text,jsonb)','EXECUTE')
       OR has_function_privilege(r,'private.clause_write_set(jsonb,jsonb,integer,text,uuid)','EXECUTE') THEN
      RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: % kan køre en privat writer',r;
    END IF;
  END LOOP;
  RAISE NOTICE 'OK: signatur og rettigheder';
END $t$;

-- ===== Task 7: læsere af helposttekst følger revisionen (spec §4.4 »Én læser af gældende helposttekst«) =====

-- clause_revision gennem hele kæden (autorisation → preflight → apply → finalize), som t5_apply.
CREATE FUNCTION pg_temp.t7_clause_revision(fx jsonb,p_payload jsonb,p_nonce text) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_msha text:=encode(extensions.digest('t7:'||p_nonce,'sha256'),'hex'); v_psha text:=repeat('7',64);
  v_element text:='clause-revision:'||(fx->>'record_key'); v_auth uuid; v_batch uuid; v_res jsonb;
BEGIN
  PERFORM set_config('request.jwt.claim.sub',fx->>'actor',true);
  PERFORM set_config('role','service_role',true);
  v_auth:=public.red_authorize_reimport(v_msha,v_psha,
    jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,
    (fx->>'source')::bigint,fx->'profile'->>'profile_id',fx->'profile'->>'profile_sha256',
    '{"person_creates":0,"source_evidence":0,"clause_revisions":1}'::jsonb,jsonb_build_object(v_element,p_payload),
    gen_random_uuid(),clock_timestamp()+interval '5 minutes');
  PERFORM set_config('role','authenticated',true);
  PERFORM public.red_preflight_reimport_authorization(v_auth,v_msha,v_psha);
  v_batch:=public.red_begin_reimport(v_auth,v_msha,v_psha);
  v_res:=public.red_apply_reimport_clause_revision(v_batch,v_element,p_payload);
  PERFORM public.red_finalize_reimport(v_batch);
  RESET role;
  RETURN v_res;
END $$;

-- Omsegmentering af det aktuelle sæt mod p_text (helpostens tekst, som manifest-builderen ville hashe den).
CREATE FUNCTION pg_temp.t7_resegment_payload(fx jsonb,p_text text,p_parts text[]) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_help uuid:=(fx->>'helpost')::uuid; v_seq int;
BEGIN
  SELECT max(coalesce(clause_set_seq,1)) INTO v_seq FROM private.source_observation WHERE parent_observation_id=v_help;
  RETURN jsonb_build_object('source_record_key',fx->>'record_key','rendition_content_sha256',repeat('2',64),
    'rendition_projection_sha256',repeat('9',64),'parent_verbatim_sha256',encode(extensions.digest(p_text,'sha256'),'hex'),
    'replaces_clause_set_seq',v_seq,'replaces_clause_set_sha256',private.clause_set_sha256(v_help,v_seq),
    'clause_rules_version','clause-rules-fixture-v2','segmenter_version','clause_segment.py@fixture',
    'ledger_sha256',repeat('e',64),'gap_charset',jsonb_build_array(' '),'clauses',pg_temp.t5_clauses(p_text,p_parts));
END $$;

-- test_clause_revision_follows_text_revision: efter en kildetekst-revision skæres en ren omsegmentering
-- (clause_revision) af den gældende tekstversion og bindes til den; basistekstens hash er forældet
-- (CLAUSE_EVIDENCE_PARENT_TEXT_DRIFT), så omsegmenteringen ikke tavst skærer mod den gamle tekst.
DO $t$
DECLARE v_actor uuid:='11000000-0000-0000-0000-00000006a701'; s jsonb; post jsonb; fx jsonb; r jsonb; v_help uuid;
  v_base text:='Anna Alfa. Gift med Bo Beta.'; v_new text:='Anna Alfa. Gift m. Bo Beta.'; v_tid uuid; v_seq int;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  s:=pg_temp.f5b_source(-65701);
  post:=pg_temp.f5b_post(-65701,s,'T7-CR',v_base,ARRAY['Anna Alfa.','Gift med Bo Beta.'],NULL,v_actor);
  v_help:=(post->>'helpost')::uuid;
  fx:=jsonb_build_object('source',-65701,'record_key','T7-CR','helpost',v_help,'text',v_base,'actor',v_actor,
    'profile',pg_temp.t5_profile(-65701));
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  r:=pg_temp.t5_apply(fx,pg_temp.t5_payload(fx,v_new,ARRAY['Anna Alfa.','Gift m. Bo Beta.']),'t7-cr-rev');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  v_tid:=(r->>'text_id')::uuid;
  -- Basistekstens hash er ikke længere helpostens tekst.
  PERFORM pg_temp.expect_error(format('SELECT pg_temp.t7_clause_revision(%L::jsonb,%L::jsonb,%L)',fx,
    pg_temp.t7_resegment_payload(fx,v_base,ARRAY['Anna Alfa. Gift med Bo Beta.']),'t7-cr-base'),'CLAUSE_EVIDENCE_PARENT_TEXT_DRIFT');
  -- Den gældende tekst: omsegmenteringen lykkes og bindes til tekstversionen.
  r:=pg_temp.t7_clause_revision(fx,pg_temp.t7_resegment_payload(fx,v_new,ARRAY['Anna Alfa. Gift m. Bo Beta.']),'t7-cr-new');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  v_seq:=(r->>'clause_set_seq')::int;
  IF v_seq<>3
     OR (SELECT count(*) FROM private.source_observation WHERE parent_observation_id=v_help AND clause_set_seq=3)<>1
     OR EXISTS (SELECT 1 FROM private.source_observation WHERE parent_observation_id=v_help AND clause_set_seq=3
                  AND (parent_text_id IS DISTINCT FROM v_tid OR verbatim_text<>v_new))
     OR EXISTS (SELECT 1 FROM private.source_observation o JOIN private.clause_disposition_current d ON d.observation_id=o.id
                 WHERE o.parent_observation_id=v_help AND o.clause_set_seq=2 AND d.disposition<>'erstattet') THEN
    RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: clause_revision efter revision %',r;
  END IF;
  RAISE NOTICE 'OK: test_clause_revision_follows_text_revision';
END $t$;

-- test_party_inputs_ignore_superseded + test_relation_persona_v3_post_text_follows_revision:
-- en post med to ægteskaber; Bo Beta er new_person_needed med dødsoplysning (D-population i relation_person_create_input),
-- Cia Ceta er new_person_needed uden (v3's genafgørelsesrække). Efter revisionen er begge relationer forældede:
-- person-create-inputtet har ingen række (og writeren afviser det gamle element), genafgørelsesrækken mister
-- hovedperson og ægteskabsnummer (partens autoritet), og post_text er den gældende tekstversion.
DO $t$
DECLARE v_actor uuid:='11000000-0000-0000-0000-00000006a702'; s jsonb; post jsonb; fx jsonb; r jsonb; c jsonb; v_help uuid;
  sp1 uuid; sp2 uuid; m jsonb; v3 jsonb; q jsonb; b jsonb; v_err text; v_c2 uuid;
  v_base text:='Anna Alfa. Gift 1890 med Bo Beta. Gift 1950 med Cia Ceta.';
  v_new text:='Anna Alfa. Gift 1890 m. Bo Beta. Gift 1950 m. Cia Ceta.';
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) VALUES (-65702,false,false,'t7');
  s:=pg_temp.f5b_source(-65702);
  post:=pg_temp.f5b_post(-65702,s,'T7-PI',v_base,ARRAY['Anna Alfa.','Gift 1890 med Bo Beta.','Gift 1950 med Cia Ceta.'],-65702,v_actor);
  v_help:=(post->>'helpost')::uuid;
  PERFORM pg_temp.f2a_event_for_state((post->>'principal')::uuid);
  c:=pg_temp.f5b_claim(-65702,s,'relation.marriage',(post->'clauses'->>1)::uuid,'Gift 1890 med Bo Beta.');
  sp1:=pg_temp.f5b_spouse(-65702,s,post,c,(post->'clauses'->>1)::uuid,'Bo Beta',1);
  c:=pg_temp.f5b_claim(-65702,s,'relation.marriage',(post->'clauses'->>2)::uuid,'Gift 1950 med Cia Ceta.');
  sp2:=pg_temp.f5b_spouse(-65702,s,post,c,(post->'clauses'->>2)::uuid,'Cia Ceta',2);
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  PERFORM red_afgoer_source_persona(sp1,0,'new_person_needed',NULL,'test',jsonb_build_object('basis','human_sheet',
    'sheet_sha256',repeat('a',64),'rows_sha256',repeat('a',64),'line',1,
    'deceased',jsonb_build_object('rule','aarstal-120-v1','cutoff_year',1906,'clause_years',jsonb_build_array(1890))));
  PERFORM red_afgoer_source_persona(sp2,0,'new_person_needed',NULL,'test',jsonb_build_object('basis','human_sheet',
    'sheet_sha256',repeat('a',64),'rows_sha256',repeat('a',64),'line',2));
  RESET ROLE;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;

  -- Før revisionen: én D-række, og genafgørelsesrækken kender hovedperson, nummer og basisteksten.
  m:=private.relation_person_create_input(-65702);
  IF (m->'expected_counts'->>'relation_person_creates')::int<>1 OR NOT m->'authorized_elements' ? ('relation-person-create:'||sp1) THEN
    RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: person-create-input før revisionen %',m->'expected_counts';
  END IF;
  v3:=private.relation_persona_v3_input(-65702);
  q:=v3->'redecide_rows'->0;
  IF jsonb_array_length(v3->'redecide_rows')<>1 OR q->>'source_persona_id'<>sp2::text
     OR (q->>'principal_person_id')::bigint IS DISTINCT FROM -65702 OR (q->>'marriage_ordinal')::int IS DISTINCT FROM 2
     OR q->>'post_text' IS DISTINCT FROM v_base OR jsonb_array_length(v3->'rows')<>0 THEN
    RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: v3-input før revisionen %',v3;
  END IF;

  fx:=jsonb_build_object('source',-65702,'record_key','T7-PI','helpost',v_help,'text',v_base,'actor',v_actor,
    'profile',pg_temp.t5_profile(-65702));
  r:=pg_temp.t5_apply(fx,pg_temp.t5_payload(fx,v_new,ARRAY['Anna Alfa.','Gift 1890 m. Bo Beta.','Gift 1950 m. Cia Ceta.']),'t7-pi-rev');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF jsonb_array_length(r->'superseded_keys')<>2 THEN RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: revisionen %',r; END IF;

  -- test_party_inputs_ignore_superseded: ingen række for den forældede relation; writeren afviser det gamle element.
  IF (private.relation_person_create_input(-65702)->'expected_counts'->>'relation_person_creates')::int<>0 THEN
    RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: person-create-input efter revisionen %',private.relation_person_create_input(-65702);
  END IF;
  b:=pg_temp.f5b_batch(-65702,v_actor,pg_temp.f5b_profile(-65702),m->'authorized_elements',m->'expected_counts');
  BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM red_apply_reimport_relation_person_create((b->>'batch')::uuid,e.key,e.value) FROM jsonb_each(m->'authorized_elements') e;
    v_err:='ingen fejl';
  EXCEPTION WHEN OTHERS THEN v_err:=SQLERRM;
  END;
  RESET ROLE;
  IF v_err NOT LIKE 'RELATION_PERSON_CREATE_CLAUSE_STALE%' AND v_err NOT LIKE 'RELATION_PERSON_CREATE_INTERPRETATION_STALE%' THEN
    RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: writeren på forældet relation gav %',v_err;
  END IF;

  -- v3: genafgørelsesrækken står (identiteten er uafklaret), men uden partens autoritet; post_text er den nye tekst.
  v3:=private.relation_persona_v3_input(-65702);
  q:=v3->'redecide_rows'->0;
  IF jsonb_array_length(v3->'redecide_rows')<>1 OR q->>'source_persona_id'<>sp2::text
     OR q->'principal_person_id'<>'null'::jsonb OR q->'marriage_ordinal'<>'null'::jsonb
     OR (q->>'clause_is_current')::boolean OR q->>'post_text' IS DISTINCT FROM v_new THEN
    RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: v3-genafgørelse efter revisionen %',q;
  END IF;
  -- En ny ægteskabspåstand på det nye sæt: v3's ægteskabsrække bærer den gældende tekst.
  SELECT id INTO v_c2 FROM private.clause_observation_current WHERE parent_observation_id=v_help AND clause_ordinal=2;
  PERFORM pg_temp.f5b_claim(-65702,s,'relation.marriage',v_c2,'Gift 1890 m. Bo Beta.');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  v3:=private.relation_persona_v3_input(-65702);
  IF jsonb_array_length(v3->'rows')<>1 OR v3->'rows'->0->>'post_text' IS DISTINCT FROM v_new THEN
    RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: v3-række efter revisionen %',v3->'rows';
  END IF;
  RAISE NOTICE 'OK: test_party_inputs_ignore_superseded';
  RAISE NOTICE 'OK: test_relation_persona_v3_post_text_follows_revision';
END $t$;

-- test_persona_detail_current_text_version: efter to revisioner er begge versioner foretrukne (append-only), men
-- red_source_persona_detail markerer præcis én som gældende: den, helpost_text_current vælger.
DO $t$
DECLARE v_actor uuid:='11000000-0000-0000-0000-00000006a703'; s jsonb; post jsonb; fx jsonb; d jsonb; tv jsonb;
  v_base text:='Anna Alfa. Gift med Bo Beta.';
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  s:=pg_temp.f5b_source(-65703);
  post:=pg_temp.f5b_post(-65703,s,'T7-PD',v_base,ARRAY['Anna Alfa.','Gift med Bo Beta.'],NULL,v_actor);
  fx:=jsonb_build_object('source',-65703,'record_key','T7-PD','helpost',post->>'helpost','text',v_base,'actor',v_actor,
    'profile',pg_temp.t5_profile(-65703));
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  PERFORM pg_temp.t5_apply(fx,pg_temp.t5_payload(fx,'Anna Alfa. Gift m. Bo Beta.',ARRAY['Anna Alfa.','Gift m. Bo Beta.']),'t7-pd-1');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  PERFORM pg_temp.t5_apply(fx,pg_temp.t5_payload(fx,'Anna Alfa. Gift m. Bo Beta',ARRAY['Anna Alfa.','Gift m. Bo Beta']),'t7-pd-2');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  d:=red_source_persona_detail((post->>'principal')::uuid);
  RESET ROLE;
  tv:=d->'mentions'->0->'text_versions';
  IF jsonb_array_length(tv)<>2
     OR (SELECT count(*) FROM jsonb_array_elements(tv) x WHERE (x->>'preferred')::boolean)<>2
     OR (SELECT count(*) FROM jsonb_array_elements(tv) x WHERE (x->>'current')::boolean)<>1
     OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(tv) x
                     WHERE (x->>'current')::boolean AND (x->>'version')::int=2 AND x->>'verbatim_text'='Anna Alfa. Gift m. Bo Beta') THEN
    RAISE EXCEPTION 'TEXT_REVISION_TEST_FAILED: persona-detaljens tekstversioner %',tv;
  END IF;
  RAISE NOTICE 'OK: test_persona_detail_current_text_version';
END $t$;

ROLLBACK;

-- test_revision_isolation_guard (Codex I2): genmålingen efter låsene kræver et nyt snapshot pr. sætning, så writeren
-- afviser REPEATABLE READ og SERIALIZABLE som første sætning (før prepare, uden låse og skrivninger). Under READ
-- COMMITTED passerer kaldet vagten; næste kontrol er rollegaten, fordi kaldet her ikke har en redaktør.
BEGIN ISOLATION LEVEL REPEATABLE READ;
DO $t$
BEGIN
  PERFORM pg_temp.expect_error($q$SELECT public.red_apply_reimport_source_text_revision(gen_random_uuid(),'source-text-revision:iso','{}'::jsonb)$q$,
    'TEXT_REVISION_ISOLATION_UNSUPPORTED');
  PERFORM pg_temp.expect_error($q$SELECT private.write_source_text_revision(gen_random_uuid(),'source-text-revision:iso','{}'::jsonb)$q$,
    'TEXT_REVISION_ISOLATION_UNSUPPORTED');
  RAISE NOTICE 'OK: test_revision_isolation_guard (repeatable read)';
END $t$;
ROLLBACK;
BEGIN ISOLATION LEVEL SERIALIZABLE;
DO $t$
BEGIN
  PERFORM pg_temp.expect_error($q$SELECT public.red_apply_reimport_source_text_revision(gen_random_uuid(),'source-text-revision:iso','{}'::jsonb)$q$,
    'TEXT_REVISION_ISOLATION_UNSUPPORTED');
  PERFORM pg_temp.expect_error($q$SELECT private.write_source_text_revision(gen_random_uuid(),'source-text-revision:iso','{}'::jsonb)$q$,
    'TEXT_REVISION_ISOLATION_UNSUPPORTED');
  RAISE NOTICE 'OK: test_revision_isolation_guard (serializable)';
END $t$;
ROLLBACK;
BEGIN ISOLATION LEVEL READ COMMITTED;
DO $t$
BEGIN
  PERFORM pg_temp.expect_error($q$SELECT public.red_apply_reimport_source_text_revision(gen_random_uuid(),'source-text-revision:iso','{}'::jsonb)$q$,
    'REIMPORT_WRITER_ROLE_FORBIDDEN');
  RAISE NOTICE 'OK: test_revision_isolation_guard (read committed passerer vagten)';
END $t$;
ROLLBACK;
\echo PASS test-source-text-revision
