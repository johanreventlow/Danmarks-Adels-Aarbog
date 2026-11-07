-- Trin 6c-3a (spec 2026-11-07-trin6c3-a6b-resten-design.md §4.4 og §4.7 pkt. 4): afstemningskvitteringen efter en
-- kildetekst-revision. private.write_text_revision_reconciliation skriver én append-only række pr. forældet nøgle
-- (genfundet/ikke_genfundet) og pr. tabt binding (genbundet/tilbagetrukket) og kontrollerer hele kæden pr. item.
-- Fixturen: t5_post (ægteskab bundet til familien, død bundet til en assertion, et forslag) revideres; ægteskabet
-- genfindes gennem relation_persona-writeren (genbrug af ægtefælle-personaen, Task 1) og genbindes til den samme
-- familie, døden genfindes og genbindes til den samme assertion, forslaget genfindes ikke. Kræver kontrakt v2
-- (reimport-writer-v2-bootstrap.sql). Alt syntetisk; én transaktion, rulles tilbage.
\set ON_ERROR_STOP on

-- Revisions-writeren kræver READ COMMITTED.
BEGIN ISOLATION LEVEL READ COMMITTED;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
\ir fixtures/source-text-revision.sql

-- De hjælpere fra test-relation-persona-reuse.sql, der skal bruges her (t6_payload, t6_apply, t6_finalize, t6_write,
-- t6_spouse), er pg_temp-funktioner i den fils egen transaktion og kan ikke \ir'es uden at køre dens tests; de
-- generklæres derfor uændret.
CREATE FUNCTION pg_temp.t6_payload(p_clause uuid,p_key text,p_raw text,p_name text,p_birth text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_co private.source_observation%ROWTYPE; v_from int;
BEGIN
  SELECT * INTO v_co FROM private.source_observation WHERE id=p_clause;
  v_from:=strpos(v_co.verbatim_text,p_raw)-1;
  IF v_from<0 THEN RAISE EXCEPTION 'T6_RAW_NOT_IN_CLAUSE'; END IF;
  RETURN jsonb_build_object('birth_raw',p_birth,'clause_observation_id',p_clause,'clause_set_seq',coalesce(v_co.clause_set_seq,1),
    'clause_set_sha256',private.clause_set_sha256(v_co.parent_observation_id,coalesce(v_co.clause_set_seq,1)),'death_raw',NULL,
    'interpretation_key',p_key,'interpretation_version',1,
    'marriage_ordinal',(SELECT o.marriage_ordinal FROM private.relation_marriage_ordinals(v_co.occurrence_id) o
                         WHERE o.interpretation_key=p_key::uuid),
    'name_from',v_from+strpos(p_raw,p_name)-1,'name_to',v_from+strpos(p_raw,p_name)-1+char_length(p_name),
    'post_offset',v_co.post_char_from+v_from,'predicate','relation.marriage','profile','relation-persona-2018-20-v1',
    'span_from',v_from,'span_to',v_from+char_length(p_raw));
END $$;

CREATE FUNCTION pg_temp.t6_apply(p_source bigint,p_actor uuid,p_elements jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE prof jsonb; b jsonb; e record;
BEGIN
  SELECT jsonb_build_object('profile_id',profile_id,'profile_sha256',profile_sha256) INTO prof
    FROM private.reimport_writer_profile WHERE source_id=p_source AND profile_id='relation-5b';
  IF prof IS NULL THEN prof:=pg_temp.f5b_profile(p_source); END IF;
  b:=pg_temp.f5b_batch(p_source,p_actor,prof,p_elements);
  SET LOCAL ROLE authenticated;
  FOR e IN SELECT * FROM jsonb_each(p_elements) LOOP
    PERFORM public.red_apply_reimport_relation_persona((b->>'batch')::uuid,e.key,e.value);
  END LOOP;
  RESET ROLE;
  RETURN b;
END $$;

CREATE FUNCTION pg_temp.t6_finalize(b jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE r jsonb;
BEGIN
  SET LOCAL ROLE authenticated;
  PERFORM public.red_finalize_reimport((b->>'batch')::uuid);
  r:=public.red_reimport_batch_result((b->>'auth')::uuid,(b->>'batch')::uuid);
  RESET ROLE;
  RETURN r;
END $$;

CREATE FUNCTION pg_temp.t6_write(p_source bigint,p_actor uuid,p_payload jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE b jsonb; v_el text:='relation-persona:'||(p_payload->>'interpretation_key'); r jsonb;
BEGIN
  b:=pg_temp.t6_apply(p_source,p_actor,jsonb_build_object(v_el,p_payload));
  r:=pg_temp.t6_finalize(b);
  RETURN b||jsonb_build_object('result',r,'receipt',
    (SELECT e.payload->'result_receipt' FROM private.reimport_event e
      WHERE e.batch_id=(b->>'batch')::uuid AND e.operation='relation_persona' AND e.element_id=v_el));
END $$;

CREATE FUNCTION pg_temp.t6_spouse(p_key text) RETURNS uuid LANGUAGE sql AS $$
  SELECT source_persona_id FROM private.interpretation_party_current WHERE interpretation_key=p_key::uuid AND party_role='spouse'
$$;

-- Fixturens id'er (nøgle → værdi), sat af opbygningen og læst af testene.
CREATE TEMP TABLE t7_fx(k text PRIMARY KEY, v text NOT NULL) ON COMMIT DROP;
CREATE FUNCTION pg_temp.t7(p_k text) RETURNS text LANGUAGE sql AS $$ SELECT v FROM t7_fx WHERE k=p_k $$;

-- Kvitteringens items. p_family/p_death: 'genbundet', 'tilbagetrukket' eller NULL (udelad bindingens række). Rækkefølgen:
-- [0] ægteskab, [1] død, [2] forslag, [3] familiebinding, [4] dødsbinding (når begge er med), til sidst forslag 2.
CREATE FUNCTION pg_temp.t7_items(p_family text DEFAULT 'genbundet',p_death text DEFAULT 'genbundet') RETURNS jsonb
LANGUAGE plpgsql AS $$
DECLARE v jsonb;
BEGIN
  v:=jsonb_build_array(
    jsonb_build_object('old_interpretation_key',pg_temp.t7('marriage_old'),'outcome','genfundet',
                       'new_interpretation_key',pg_temp.t7('marriage_new')),
    jsonb_build_object('old_interpretation_key',pg_temp.t7('death_old'),'outcome','genfundet',
                       'new_interpretation_key',pg_temp.t7('death_new')),
    jsonb_build_object('old_interpretation_key',pg_temp.t7('proposed_old'),'outcome','ikke_genfundet'));
  IF p_family='genbundet' THEN
    v:=v||jsonb_build_object('old_interpretation_key',pg_temp.t7('marriage_old'),'old_promotion_id',pg_temp.t7('family_prom_old'),
                             'outcome','genbundet','new_interpretation_key',pg_temp.t7('marriage_new'),
                             'new_promotion_id',pg_temp.t7('family_prom_new'));
  ELSIF p_family='tilbagetrukket' THEN
    v:=v||jsonb_build_object('old_interpretation_key',pg_temp.t7('marriage_old'),'old_promotion_id',pg_temp.t7('family_prom_old'),
                             'outcome','tilbagetrukket','svar','T','ref','kort:1');
  END IF;
  IF p_death='genbundet' THEN
    v:=v||jsonb_build_object('old_interpretation_key',pg_temp.t7('death_old'),'old_promotion_id',pg_temp.t7('assertion_prom_old'),
                             'outcome','genbundet','new_interpretation_key',pg_temp.t7('death_new'),
                             'new_promotion_id',pg_temp.t7('assertion_prom_new'));
  ELSIF p_death='tilbagetrukket' THEN
    v:=v||jsonb_build_object('old_interpretation_key',pg_temp.t7('death_old'),'old_promotion_id',pg_temp.t7('assertion_prom_old'),
                             'outcome','tilbagetrukket','svar','ved_ikke','ref','kort:2');
  END IF;
  RETURN v||jsonb_build_object('old_interpretation_key',pg_temp.t7('proposed2_old'),'outcome','ikke_genfundet');
END $$;

-- Kald writeren som ejer med aktøren sat i transaktionen (ceremoniens vej).
CREATE FUNCTION pg_temp.t7_call(p_items jsonb,p_context jsonb DEFAULT '{"basis":"t7 fixture"}') RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub',pg_temp.t7('actor'),true);
  RETURN private.write_text_revision_reconciliation(pg_temp.t7('batch')::uuid,p_items,p_context);
END $$;

-- Forventet fejl: writeren skal fejle med p_code (præfiks); intet skrives (delttransaktionen rulles tilbage).
CREATE FUNCTION pg_temp.t7_expect(p_label text,p_items jsonb,p_code text,p_context jsonb DEFAULT '{"basis":"t7 fixture"}')
RETURNS void LANGUAGE plpgsql AS $$
DECLARE v_err text;
BEGIN
  BEGIN
    PERFORM pg_temp.t7_call(p_items,p_context);
    v_err:='ingen fejl';
  EXCEPTION WHEN OTHERS THEN v_err:=SQLERRM;
  END;
  IF v_err NOT LIKE p_code||'%' THEN
    RAISE EXCEPTION 'RECONCILIATION_TEST_FAILED: % gav %, forventet %',p_label,v_err,p_code;
  END IF;
  IF EXISTS (SELECT 1 FROM private.text_revision_reconciliation WHERE revision_batch_id=pg_temp.t7('batch')::uuid) THEN
    RAISE EXCEPTION 'RECONCILIATION_TEST_FAILED: % efterlod rækker',p_label;
  END IF;
  RAISE NOTICE 'OK: %',p_label;
END $$;

-- Opbygning: post, revision, genfund og genbinding; et uvedkommende ægteskab (ægtefællens egen post) bundet til den
-- samme familie.
DO $t$
DECLARE v_actor uuid:='11000000-0000-0000-0000-0000006c3b01'; fx jsonb; r jsonb; c2 jsonb; c3 jsonb; c4 jsonb; c5 jsonb; p jsonb; w jsonb; m2 jsonb;
  pv jsonb; items jsonb; v_cl uuid[]; v_int uuid:=gen_random_uuid(); v_key uuid:=gen_random_uuid(); v_mnew uuid; v_m2 uuid;
  v_fprom uuid; v_m2prom uuid; v_aprom uuid;
BEGIN
  fx:=pg_temp.t5_post(-67101,v_actor,true,true);
  -- Et forslag mere på klausul 1 (samme prædikat som t5_posts forslag), så to forældede nøgler kan pege på samme nye.
  c5:=pg_temp.f5b_claim(-67101,fx->'src','relation.marriage',(fx->'post'->'clauses'->>0)::uuid,'Anna Alfa');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  r:=pg_temp.t5_apply(fx,pg_temp.t5_payload(fx,'Anna Alfa. Gift m. Bo Beta.',ARRAY['Anna Alfa.','Gift m. Bo Beta.']),'t7');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF jsonb_array_length(r->'superseded_keys')<>4 OR jsonb_array_length(r->'binding_loss')<>2 THEN
    RAISE EXCEPTION 'RECONCILIATION_TEST_FAILED: revisionen %',r;
  END IF;
  v_cl:=ARRAY(SELECT id FROM private.clause_observation_current WHERE parent_observation_id=(fx->>'helpost')::uuid
               ORDER BY clause_ordinal);

  -- Ægteskabet genfindes gennem writeren; ægtefælle-personaen genbruges (Task 1).
  c2:=pg_temp.f5b_claim(-67101,fx->'src','relation.marriage',v_cl[2],'Gift m. Bo Beta.');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  p:=pg_temp.t6_payload(v_cl[2],c2->>'key','Gift m. Bo Beta.','Bo Beta');
  w:=pg_temp.t6_write(-67101,v_actor,p);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF pg_temp.t6_spouse(c2->>'key') IS DISTINCT FROM (fx->>'spouse_persona')::uuid THEN
    RAISE EXCEPTION 'RECONCILIATION_TEST_FAILED: ægtefælle-personaen blev ikke genbrugt %',w->'receipt';
  END IF;

  -- Et uvedkommende ægteskab: ægtefællens egen post (hovedperson Bo, ægtefælle Anna), samme kilde, ingen ny familie.
  m2:=pg_temp.f2a_marriage(-67101,fx->'src','T7-BO',-67102,-67101,v_actor,1,1,false);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;

  -- Begge ægteskaber afgøres og bindes til den gamle familie.
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_decisions(-67101);
  PERFORM red_decide_relation_interpretations(-67101,pv->>'set_sha256');
  RESET ROLE;
  SELECT id INTO v_mnew FROM private.interpretation_current WHERE interpretation_key=(c2->>'key')::uuid AND status='accepted';
  SELECT id INTO v_m2 FROM private.interpretation_current WHERE interpretation_key=(m2->'claim'->>'key')::uuid AND status='accepted';
  IF v_mnew IS NULL OR v_m2 IS NULL THEN RAISE EXCEPTION 'RECONCILIATION_TEST_FAILED: ægteskaberne er ikke accepteret'; END IF;
  items:=jsonb_build_array(jsonb_build_object('interpretation_id',v_mnew::text,'family_id',(fx->>'family')::bigint),
                           jsonb_build_object('interpretation_id',v_m2::text,'family_id',(fx->>'family')::bigint));
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_promotions(-67101,items);
  PERFORM red_promote_relation_interpretations_batch(-67101,items,pv->>'preview_sha256');
  RESET ROLE;
  SELECT id INTO v_fprom FROM private.interpretation_promotion WHERE interpretation_id=v_mnew AND target_type='family';
  SELECT id INTO v_m2prom FROM private.interpretation_promotion WHERE interpretation_id=v_m2 AND target_type='family';
  IF v_fprom IS NULL OR v_m2prom IS NULL THEN RAISE EXCEPTION 'RECONCILIATION_TEST_FAILED: ægteskaberne er ikke bundet'; END IF;

  -- Døden genfindes på den nye klausul 1, afgøres og bindes til den samme assertion.
  INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,
    predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
    VALUES (v_int,v_key,1,-67101,(fx->'post'->>'principal')::uuid,'property','person.death',to_jsonb('1850'::text),'1.0',
      'source_statement',1,'proposed','fixture',(fx->'src'->>'run')::uuid);
  INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
    VALUES (v_int,v_cl[1],'supporting',1);
  PERFORM set_config('app.change_set_id','',true);
  SET LOCAL ROLE authenticated;
  PERFORM public.red_decide_interpretation(v_int,1,'accepted','{"basis":"t7 fixture"}');
  RESET ROLE;
  SELECT ic.id INTO v_int FROM private.interpretation_current ic WHERE ic.interpretation_key=v_key;
  items:=jsonb_build_array(jsonb_build_object('interpretation_id',v_int::text,'target_type','assertion',
                                              'target_id',(fx->>'assertion')::bigint));
  SET LOCAL ROLE authenticated;
  pv:=public.red_preview_interpretation_promotions(items);
  PERFORM public.red_promote_interpretations_batch(items,pv->>'preview_hash');
  PERFORM set_config('app.change_set_id','',true);
  RESET ROLE;
  SELECT id INTO v_aprom FROM private.interpretation_promotion WHERE interpretation_id=v_int AND target_type='assertion';
  IF v_aprom IS NULL THEN RAISE EXCEPTION 'RECONCILIATION_TEST_FAILED: døden er ikke bundet'; END IF;
  -- To nye forslag på den nye klausul 1: samme prædikat som det gamle forslag, og et andet prædikat.
  c3:=pg_temp.f5b_claim(-67101,fx->'src','relation.marriage',v_cl[1],'Anna Alfa.');
  c4:=pg_temp.f5b_claim(-67101,fx->'src','relation.child',v_cl[1],'Anna Alfa.');
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;

  INSERT INTO t7_fx(k,v) VALUES
    ('actor',v_actor::text),('batch',r->>'batch_id'),('element','source-text-revision:'||(fx->>'record_key')),
    ('source','-67101'),('family',fx->>'family'),('assertion',fx->>'assertion'),('principal',fx->'post'->>'principal'),
    ('marriage_old',fx->>'marriage_key'),('death_old',fx->>'death_key'),('proposed_old',fx->>'proposed_key'),
    ('family_prom_old',fx->>'family_promotion'),('assertion_prom_old',fx->>'assertion_promotion'),
    ('marriage_new',c2->>'key'),('death_new',v_key::text),('death_new_id',v_int::text),
    ('family_prom_new',v_fprom::text),('assertion_prom_new',v_aprom::text),
    ('m2_key',m2->'claim'->>'key'),('m2_prom',v_m2prom::text),('proposed_new',c3->>'key'),('proposed2_old',c5->>'key'),('child_new',c4->>'key');
  -- Revisionens tab er præcis de to gamle bindinger.
  IF (SELECT jsonb_agg(b->>'promotion_id' ORDER BY b->>'promotion_id') FROM jsonb_array_elements(r->'binding_loss') b)
     IS DISTINCT FROM (SELECT jsonb_agg(x ORDER BY x) FROM unnest(ARRAY[fx->>'family_promotion',fx->>'assertion_promotion']) x) THEN
    RAISE EXCEPTION 'RECONCILIATION_TEST_FAILED: binding_loss %',r->'binding_loss';
  END IF;
  RAISE NOTICE 'OK: fixture (revision, genfund, genbinding)';
END $t$;

-- Mængden (regel 2): en manglende binding, en ekstra nøgle og en dobbelt nøgle.
DO $t$
BEGIN
  PERFORM pg_temp.t7_expect('test_mangler_binding',pg_temp.t7_items('genbundet',NULL),'AFSTEMNING_MAENGDE_AFVIGER');
  PERFORM pg_temp.t7_expect('test_ekstra_noegle',pg_temp.t7_items()||jsonb_build_object(
    'old_interpretation_key',pg_temp.t7('m2_key'),'outcome','ikke_genfundet'),'AFSTEMNING_MAENGDE_AFVIGER');
  PERFORM pg_temp.t7_expect('test_dobbelt_noegle',pg_temp.t7_items()||jsonb_build_object(
    'old_interpretation_key',pg_temp.t7('proposed_old'),'outcome','ikke_genfundet'),'AFSTEMNING_MAENGDE_AFVIGER');
  PERFORM pg_temp.t7_expect('test_binding_under_anden_noegle',
    (SELECT jsonb_agg(CASE WHEN e->>'old_promotion_id'=pg_temp.t7('assertion_prom_old')
                           THEN jsonb_set(jsonb_set(e,'{old_interpretation_key}',to_jsonb(pg_temp.t7('marriage_old'))),
                                          '{outcome}','"tilbagetrukket"')-'new_interpretation_key'-'new_promotion_id'
                                || '{"svar":"T","ref":"kort:9"}'
                           ELSE e END)
       FROM jsonb_array_elements(pg_temp.t7_items()) e),'AFSTEMNING_MAENGDE_AFVIGER',jsonb_build_object('svar_sha256',repeat('a',64)));
END $t$;

-- Inputformen: ukendt felt, manglende ny nøgle ved genfundet, ny nøgle ved ikke_genfundet.
DO $t$
BEGIN
  PERFORM pg_temp.t7_expect('test_ukendt_felt',
    jsonb_set(pg_temp.t7_items(),'{2,note}','"x"'),'AFSTEMNING_INPUT_UGYLDIG');
  PERFORM pg_temp.t7_expect('test_genfundet_uden_ny_noegle',
    jsonb_set(pg_temp.t7_items(),'{0,new_interpretation_key}','null'),'AFSTEMNING_INPUT_UGYLDIG');
  PERFORM pg_temp.t7_expect('test_ikke_genfundet_med_ny_noegle',
    jsonb_set(pg_temp.t7_items(),'{2,new_interpretation_key}',to_jsonb(pg_temp.t7('death_new'))),'AFSTEMNING_INPUT_UGYLDIG');
  PERFORM pg_temp.t7_expect('test_svar_paa_genfundet',
    jsonb_set(pg_temp.t7_items(),'{0,svar}','"T"'),'AFSTEMNING_INPUT_UGYLDIG');
  PERFORM pg_temp.t7_expect('test_svar_i_konteksten',pg_temp.t7_items(),'AFSTEMNING_INPUT_UGYLDIG','{"svar":"T"}');
END $t$;

-- Svaret (regel 4): tilbagetrukket uden svar, med ukendt svar, uden ref, og uden svar_sha256 i konteksten.
DO $t$
DECLARE v_ctx jsonb:=jsonb_build_object('svar_sha256',repeat('b',64)); v jsonb:=pg_temp.t7_items('genbundet','tilbagetrukket');
BEGIN
  PERFORM pg_temp.t7_expect('test_mangler_svar',jsonb_set(v,'{4}',(v->4)-'svar'),'AFSTEMNING_SVAR_MANGLER',v_ctx);
  PERFORM pg_temp.t7_expect('test_ukendt_svar',jsonb_set(v,'{4,svar}','"V"'),'AFSTEMNING_SVAR_MANGLER',v_ctx);
  PERFORM pg_temp.t7_expect('test_mangler_ref',jsonb_set(v,'{4}',(v->4)-'ref'),'AFSTEMNING_SVAR_MANGLER',v_ctx);
  PERFORM pg_temp.t7_expect('test_mangler_svar_sha256',v,'AFSTEMNING_SVAR_MANGLER');
  PERFORM pg_temp.t7_expect('test_ugyldig_svar_sha256',v,'AFSTEMNING_SVAR_MANGLER','{"svar_sha256":"abc"}');
END $t$;

-- Kæden (regel 3): en ny nøgle med et andet prædikat, og (test_uvedkommende_promotion_samme_familie) en eksisterende,
-- gyldig promotion mod samme familie for en anden relation, angivet som genbundet — både under den nye nøgle og
-- under sin egen nøgle.
DO $t$
DECLARE v jsonb:=pg_temp.t7_items();
BEGIN
  PERFORM pg_temp.t7_expect('test_andet_praedikat',
    jsonb_set(v,'{2}',jsonb_build_object('old_interpretation_key',pg_temp.t7('proposed_old'),'outcome','genfundet',
      'new_interpretation_key',pg_temp.t7('child_new'))),'AFSTEMNING_KAEDE_AFVIGER');
  PERFORM pg_temp.t7_expect('test_ny_noegle_to_gange',
    jsonb_set(v,'{2}',jsonb_build_object('old_interpretation_key',pg_temp.t7('proposed_old'),'outcome','genfundet',
      'new_interpretation_key',pg_temp.t7('death_new'))),'AFSTEMNING_KAEDE_AFVIGER');
  PERFORM pg_temp.t7_expect('test_genfundet_til_anden_post',
    jsonb_set(v,'{2}',jsonb_build_object('old_interpretation_key',pg_temp.t7('proposed_old'),'outcome','genfundet',
      'new_interpretation_key',pg_temp.t7('m2_key'))),'AFSTEMNING_KAEDE_AFVIGER');
  PERFORM pg_temp.t7_expect('test_uvedkommende_promotion_samme_familie (ny nøgle)',
    jsonb_set(v,'{3,new_promotion_id}',to_jsonb(pg_temp.t7('m2_prom'))),'AFSTEMNING_KAEDE_AFVIGER');
  PERFORM pg_temp.t7_expect('test_uvedkommende_promotion_samme_familie (egen nøgle)',
    jsonb_set(jsonb_set(jsonb_set(v,'{3,new_promotion_id}',to_jsonb(pg_temp.t7('m2_prom'))),
      '{3,new_interpretation_key}',to_jsonb(pg_temp.t7('m2_key'))),
      '{0,new_interpretation_key}',to_jsonb(pg_temp.t7('m2_key'))),'AFSTEMNING_KAEDE_AFVIGER');
  PERFORM pg_temp.t7_expect('test_to_gamle_noegler_samme_nye',
    jsonb_set(jsonb_set(v,'{2}',jsonb_build_object('old_interpretation_key',pg_temp.t7('proposed_old'),'outcome','genfundet',
      'new_interpretation_key',pg_temp.t7('proposed_new'))),
      '{5}',jsonb_build_object('old_interpretation_key',pg_temp.t7('proposed2_old'),'outcome','genfundet',
      'new_interpretation_key',pg_temp.t7('proposed_new'))),'AFSTEMNING_KAEDE_AFVIGER');
  PERFORM pg_temp.t7_expect('test_genbundet_uden_genfundet',
    jsonb_set(v,'{0}',jsonb_build_object('old_interpretation_key',pg_temp.t7('marriage_old'),'outcome','ikke_genfundet')),
    'AFSTEMNING_KAEDE_AFVIGER');
  PERFORM pg_temp.t7_expect('test_genbundet_anden_ny_noegle_end_genfundet',
    jsonb_set(v,'{0,new_interpretation_key}',to_jsonb(pg_temp.t7('m2_key'))),'AFSTEMNING_KAEDE_AFVIGER');
END $t$;

-- Kæden, ét led ad gangen (hver i en delttransaktion, der rulles tilbage): en ny nøgle der kun afviger i persona
-- (fakta), i helpost, i principal eller i ægtefælle-persona (relationer), angivet som genfundet.
DO $t$
DECLARE v_case text; v_int uuid; v_key uuid; v_cl uuid[]; v_m2cl uuid; v_ref uuid; v_persona uuid; v_mention uuid;
BEGIN
  v_cl:=ARRAY(SELECT o.id FROM private.clause_observation_current o
                JOIN private.source_observation h ON h.id=o.parent_observation_id
               WHERE h.id=(SELECT parent_observation_id FROM private.source_observation
                            WHERE id=(SELECT observation_id FROM private.interpretation_observation
                                       WHERE interpretation_id=pg_temp.t7('death_new_id')::uuid))
               ORDER BY o.clause_ordinal);
  SELECT io.observation_id INTO v_m2cl FROM private.interpretation_observation io
    JOIN private.interpretation i ON i.id=io.interpretation_id
   WHERE i.interpretation_key=pg_temp.t7('m2_key')::uuid ORDER BY i.version LIMIT 1;
  FOREACH v_case IN ARRAY ARRAY['persona','helpost','principal','spouse'] LOOP
    BEGIN
      v_int:=gen_random_uuid(); v_key:=gen_random_uuid(); v_ref:=gen_random_uuid();
      IF v_case IN ('persona','helpost') THEN
        INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,
          predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
        SELECT v_int,v_key,1,i.source_id,CASE v_case WHEN 'persona' THEN NULL ELSE i.source_persona_id END,
               i.interpretation_kind,i.predicate,i.value,i.schema_version,i.derivation_kind,i.confidence,'proposed',i.method,
               i.extraction_run_id
          FROM private.interpretation i WHERE i.id=pg_temp.t7('death_new_id')::uuid;
        INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
          VALUES (v_int,CASE v_case WHEN 'persona' THEN v_cl[1] ELSE v_m2cl END,'supporting',1);
        PERFORM pg_temp.t7_expect('test_kaede_'||v_case,
          jsonb_set(pg_temp.t7_items('genbundet','tilbagetrukket'),'{1,new_interpretation_key}',to_jsonb(v_key::text)),
          'AFSTEMNING_KAEDE_AFVIGER',jsonb_build_object('svar_sha256',repeat('d',64)));
      ELSE
        INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,
          predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
        SELECT v_int,v_key,1,i.source_id,NULL,i.interpretation_kind,i.predicate,i.value,i.schema_version,i.derivation_kind,
               i.confidence,'proposed',i.method,i.extraction_run_id
          FROM private.interpretation_current i WHERE i.interpretation_key=pg_temp.t7('marriage_new')::uuid;
        INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
          VALUES (v_int,v_cl[2],'supporting',1);
        IF v_case='principal' THEN
          -- kun ægtefællen (den genbrugte persona), ingen principal
          v_persona:=pg_temp.t6_spouse(pg_temp.t7('marriage_new'));
        ELSE
          -- samme principal, en anden ægtefælle-persona med mention på samme klausul
          INSERT INTO private.source_persona(source_id,persona_key,created_run_id)
            SELECT -67101,'T7-SPOUSE-2',extraction_run_id FROM private.interpretation WHERE id=v_int RETURNING id INTO v_persona;
          INSERT INTO private.source_mention(observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id)
            SELECT v_cl[2],'person',8,15,'Bo Beta',extraction_run_id FROM private.interpretation WHERE id=v_int
            RETURNING id INTO v_mention;
          INSERT INTO private.source_persona_mention(persona_id,mention_id,mention_role,ordinal) VALUES (v_persona,v_mention,'spouse',1);
          INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,post_offset,origin,origin_ref)
            VALUES (v_key,'principal',1,pg_temp.t7('principal')::uuid,7,'relation_persona',v_ref);
        END IF;
        INSERT INTO private.interpretation_party(interpretation_key,party_role,version,source_persona_id,marriage_ordinal,post_offset,
          origin,origin_ref) VALUES (v_key,'spouse',1,v_persona,1,7,'relation_persona',v_ref);
        PERFORM pg_temp.t7_expect('test_kaede_'||v_case,
          jsonb_set(pg_temp.t7_items('tilbagetrukket','genbundet'),'{0,new_interpretation_key}',to_jsonb(v_key::text)),
          'AFSTEMNING_KAEDE_AFVIGER',jsonb_build_object('svar_sha256',repeat('d',64)));
      END IF;
      RAISE EXCEPTION 'T7_ROLLBACK';
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM<>'T7_ROLLBACK' THEN RAISE; END IF;
    END;
  END LOOP;
END $t$;

-- Status (regel 3): dødens nye nøgle får en ny gældende version, unresolved (genfundet tilladt, genbundet ikke) eller
-- rejected (heller ikke genfundet).
DO $t$
DECLARE v_status text; v_id uuid;
BEGIN
  FOREACH v_status IN ARRAY ARRAY['unresolved','rejected'] LOOP
    BEGIN
      v_id:=gen_random_uuid();
      INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,predicate,
        value,schema_version,derivation_kind,confidence,status,method,extraction_run_id,supersedes_id,decision_evidence,
        decided_by,decided_by_name,decided_at)
      SELECT v_id,i.interpretation_key,i.version+1,i.source_id,i.source_persona_id,i.interpretation_kind,i.predicate,i.value,
             i.schema_version,i.derivation_kind,i.confidence,v_status,i.method,i.extraction_run_id,i.id,'{"basis":"t7 fixture"}',
             pg_temp.t7('actor')::uuid,'t7',clock_timestamp()
        FROM private.interpretation_current i WHERE i.interpretation_key=pg_temp.t7('death_new')::uuid;
      INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
      SELECT v_id,observation_id,evidence_role,ordinal FROM private.interpretation_observation
       WHERE interpretation_id=pg_temp.t7('death_new_id')::uuid;
      IF v_status='unresolved' THEN
        PERFORM pg_temp.t7_expect('test_genbundet_ikke_accepteret',pg_temp.t7_items(),'AFSTEMNING_KAEDE_AFVIGER');
      ELSE
        PERFORM pg_temp.t7_expect('test_genfundet_afvist',pg_temp.t7_items('genbundet','tilbagetrukket'),
          'AFSTEMNING_KAEDE_AFVIGER',jsonb_build_object('svar_sha256',repeat('e',64)));
      END IF;
      RAISE EXCEPTION 'T7_ROLLBACK';
    EXCEPTION WHEN raise_exception THEN
      IF SQLERRM<>'T7_ROLLBACK' THEN RAISE; END IF;
    END;
  END LOOP;
END $t$;

-- Målet (regel 3): den nye nøgle er også bundet til en anden assertion; den binding angivet som genbundet.
DO $t$
DECLARE v_fact bigint; v_assert bigint; items jsonb; pv jsonb; v_prom uuid; v_err text;
BEGIN
  BEGIN
    INSERT INTO fact(subjekt_type,subjekt_id,faktatype) VALUES ('person',-67101,'død') RETURNING id INTO v_fact;
    INSERT INTO assertion(target_type,target_id,date_raw,calendar,uforanderlig) VALUES ('fact',v_fact,'1850','gregoriansk',true)
      RETURNING id INTO v_assert;
    INSERT INTO conclusion(target_type,target_id,valgt_assertion_id,status) VALUES ('fact',v_fact,v_assert,'afklaret');
    items:=jsonb_build_array(jsonb_build_object('interpretation_id',pg_temp.t7('death_new_id'),'target_type','assertion',
                                                'target_id',v_assert));
    PERFORM set_config('request.jwt.claim.sub',pg_temp.t7('actor'),true);
    PERFORM set_config('app.change_set_id','',true);
    SET LOCAL ROLE authenticated;
    pv:=public.red_preview_interpretation_promotions(items);
    PERFORM public.red_promote_interpretations_batch(items,pv->>'preview_hash');
    PERFORM set_config('app.change_set_id','',true);
    RESET ROLE;
    SELECT id INTO v_prom FROM private.interpretation_promotion WHERE target_type='assertion' AND target_id=v_assert;
    IF v_prom IS NULL THEN RAISE EXCEPTION 'RECONCILIATION_TEST_FAILED: anden assertion ikke bundet'; END IF;
    PERFORM pg_temp.t7_expect('test_forkert_maal',
      jsonb_set(pg_temp.t7_items(),'{4,new_promotion_id}',to_jsonb(v_prom::text)),'AFSTEMNING_MAAL_AFVIGER');
    RAISE EXCEPTION 'T7_ROLLBACK';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM<>'T7_ROLLBACK' THEN RAISE; END IF;
  END;
END $t$;

-- Bindingen (regel 3): familiens ægtefællerække fjernes, så den nye bindings tilstand ikke længere holder.
DO $t$
BEGIN
  BEGIN
    PERFORM set_config('app.change_set_id','',true);
    DELETE FROM family_member WHERE family_id=pg_temp.t7('family')::bigint AND person_id=-67102 AND rolle='partner';
    PERFORM pg_temp.t7_expect('test_ugyldig_binding',pg_temp.t7_items(),'AFSTEMNING_BINDING_UGYLDIG');
    RAISE EXCEPTION 'T7_ROLLBACK';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM<>'T7_ROLLBACK' THEN RAISE; END IF;
  END;
END $t$;

-- Aktøren: uden aktør i transaktionen afvises kaldet.
DO $t$
DECLARE v_err text;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','',true);
  BEGIN
    PERFORM private.write_text_revision_reconciliation(pg_temp.t7('batch')::uuid,pg_temp.t7_items(),'{}');
    v_err:='ingen fejl';
  EXCEPTION WHEN OTHERS THEN v_err:=SQLERRM;
  END;
  IF v_err NOT LIKE 'REIMPORT_WRITER_ROLE_FORBIDDEN%' THEN
    RAISE EXCEPTION 'RECONCILIATION_TEST_FAILED: uden aktør gav %',v_err;
  END IF;
  RAISE NOTICE 'OK: test_uden_aktoer';
END $t$;

-- Tilbagetrækning (rulles tilbage): dødens binding trækkes tilbage med svaret ved_ikke; svar og ref står i rækkens
-- kontekst sammen med svarfilens hash. Forslaget genfindes her som et nyt forslag med samme prædikat (uden parter).
DO $t$
DECLARE r jsonb; v_ctx jsonb:=jsonb_build_object('svar_sha256',repeat('c',64),'basis','t7 fixture'); v_row record;
BEGIN
  BEGIN
    r:=pg_temp.t7_call(jsonb_set(pg_temp.t7_items('genbundet','tilbagetrukket'),'{2}',
      jsonb_build_object('old_interpretation_key',pg_temp.t7('proposed_old'),'outcome','genfundet',
                         'new_interpretation_key',pg_temp.t7('proposed_new'))),v_ctx);
    IF r<>'{"genbundet":1,"tilbagetrukket":1,"genfundet":3,"ikke_genfundet":1}'::jsonb THEN
      RAISE EXCEPTION 'RECONCILIATION_TEST_FAILED: tilbagetrækning gav %',r;
    END IF;
    SELECT * INTO v_row FROM private.text_revision_reconciliation
     WHERE old_promotion_id=pg_temp.t7('assertion_prom_old')::uuid;
    IF v_row.outcome<>'tilbagetrukket' OR v_row.new_interpretation_key IS NOT NULL OR v_row.new_promotion_id IS NOT NULL
       OR v_row.context<>v_ctx||'{"svar":"ved_ikke","ref":"kort:2"}'::jsonb
       OR v_row.old_interpretation_key<>pg_temp.t7('death_old')::uuid THEN
      RAISE EXCEPTION 'RECONCILIATION_TEST_FAILED: tilbagetrækningsrækken %',to_jsonb(v_row);
    END IF;
    IF (SELECT context FROM private.text_revision_reconciliation
         WHERE old_interpretation_key=pg_temp.t7('death_old')::uuid AND old_promotion_id IS NULL)<>v_ctx THEN
      RAISE EXCEPTION 'RECONCILIATION_TEST_FAILED: genfundet-rækkens kontekst';
    END IF;
    RAISE EXCEPTION 'T7_ROLLBACK';
  EXCEPTION WHEN raise_exception THEN
    IF SQLERRM<>'T7_ROLLBACK' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'OK: test_tilbagetrukket';
END $t$;

-- Fuld, korrekt kvittering: antallene, én række pr. item med revisionens event, aktøren og konteksten.
DO $t$
DECLARE r jsonb; v_n int;
BEGIN
  r:=pg_temp.t7_call(pg_temp.t7_items());
  IF r<>'{"genbundet":2,"tilbagetrukket":0,"genfundet":2,"ikke_genfundet":2}'::jsonb THEN
    RAISE EXCEPTION 'RECONCILIATION_TEST_FAILED: fuld kvittering gav %',r;
  END IF;
  SELECT count(*) INTO v_n FROM private.text_revision_reconciliation
   WHERE revision_batch_id=pg_temp.t7('batch')::uuid AND revision_element_id=pg_temp.t7('element')
     AND decided_by=pg_temp.t7('actor')::uuid AND decided_by_name='5b fixture' AND context='{"basis":"t7 fixture"}';
  IF v_n<>6 THEN RAISE EXCEPTION 'RECONCILIATION_TEST_FAILED: % rækker',v_n; END IF;
  IF NOT EXISTS (SELECT 1 FROM private.text_revision_reconciliation
                  WHERE old_interpretation_key=pg_temp.t7('marriage_old')::uuid
                    AND old_promotion_id=pg_temp.t7('family_prom_old')::uuid AND outcome='genbundet'
                    AND new_interpretation_key=pg_temp.t7('marriage_new')::uuid
                    AND new_promotion_id=pg_temp.t7('family_prom_new')::uuid)
     OR NOT EXISTS (SELECT 1 FROM private.text_revision_reconciliation
                     WHERE old_interpretation_key=pg_temp.t7('proposed_old')::uuid AND old_promotion_id IS NULL
                       AND outcome='ikke_genfundet' AND new_interpretation_key IS NULL) THEN
    RAISE EXCEPTION 'RECONCILIATION_TEST_FAILED: rækkernes indhold';
  END IF;
  RAISE NOTICE 'OK: test_fuld_kvittering';
END $t$;

-- Endelig: et nyt kald for samme batch afvises; rækkerne kan ikke ændres, slettes eller tømmes.
DO $t$
DECLARE v_err text; v_op text;
BEGIN
  BEGIN
    PERFORM pg_temp.t7_call(pg_temp.t7_items());
    v_err:='ingen fejl';
  EXCEPTION WHEN OTHERS THEN v_err:=SQLERRM;
  END;
  IF v_err NOT LIKE 'AFSTEMNING_FINDES_ALLEREDE%' THEN
    RAISE EXCEPTION 'RECONCILIATION_TEST_FAILED: andet kald gav %',v_err;
  END IF;
  FOREACH v_op IN ARRAY ARRAY['UPDATE private.text_revision_reconciliation SET outcome=outcome',
                              'DELETE FROM private.text_revision_reconciliation',
                              'TRUNCATE private.text_revision_reconciliation'] LOOP
    BEGIN
      EXECUTE v_op;
      v_err:='ingen fejl';
    EXCEPTION WHEN OTHERS THEN v_err:=SQLERRM;
    END;
    IF v_err NOT LIKE 'EVIDENCE_APPEND_ONLY%' THEN
      RAISE EXCEPTION 'RECONCILIATION_TEST_FAILED: % gav %',v_op,v_err;
    END IF;
  END LOOP;
  IF (SELECT count(*) FROM private.text_revision_reconciliation WHERE revision_batch_id=pg_temp.t7('batch')::uuid)<>6 THEN
    RAISE EXCEPTION 'RECONCILIATION_TEST_FAILED: rækkerne ændret';
  END IF;
  RAISE NOTICE 'OK: test_append_only (andet kald, UPDATE, DELETE, TRUNCATE)';
END $t$;

-- Rettigheder: hverken authenticated eller anon kan kalde writeren eller læse tabellen.
DO $t$
DECLARE v_role text; v_state text;
BEGIN
  FOREACH v_role IN ARRAY ARRAY['authenticated','anon'] LOOP
    PERFORM set_config('request.jwt.claim.sub',pg_temp.t7('actor'),true);
    EXECUTE format('SET LOCAL ROLE %I',v_role);
    BEGIN
      PERFORM private.write_text_revision_reconciliation(pg_temp.t7('batch')::uuid,'[]','{}');
      v_state:='ingen fejl';
    EXCEPTION WHEN OTHERS THEN v_state:=SQLSTATE;
    END;
    RESET ROLE;
    IF v_state<>'42501' THEN RAISE EXCEPTION 'RECONCILIATION_TEST_FAILED: % kaldte writeren (%)',v_role,v_state; END IF;
    EXECUTE format('SET LOCAL ROLE %I',v_role);
    BEGIN
      PERFORM 1 FROM private.text_revision_reconciliation;
      v_state:='ingen fejl';
    EXCEPTION WHEN OTHERS THEN v_state:=SQLSTATE;
    END;
    RESET ROLE;
    IF v_state<>'42501' THEN RAISE EXCEPTION 'RECONCILIATION_TEST_FAILED: % læste tabellen (%)',v_role,v_state; END IF;
  END LOOP;
  RAISE NOTICE 'OK: test_authenticated_og_anon_afvist';
END $t$;

ROLLBACK;
\echo PASS test-text-revision-reconciliation
