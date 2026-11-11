-- Trin 6d-3 (spec §2.2, §5.1.1): tekstfoldning i ordvinduet og ægteskabsnummeret. Opdigtede navne og negative id'er.
-- Fælles tilfælde med Python-tvillingen (Task 4): tests/fixtures/relation-fold-cases.json. Konvention: w_from/w_to er
-- originaltekstens 0-baserede tegnpositioner (w_to eksklusiv) for det ENESTE vindue; null/null = ikke præcis ét vindue.
-- Køres fra repo-roden (som CI), fordi fixturen læses med en relativ sti.
\set ON_ERROR_STOP on
\set fold_cases `cat tests/fixtures/relation-fold-cases.json`
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
CREATE TEMP TABLE t3_fold_cases ON COMMIT DROP AS
  SELECT c->>'id' AS id,c->>'text' AS text,c->>'raw' AS raw,c->>'text_form' AS text_form,
         (c->>'w_from')::integer AS w_from,(c->>'w_to')::integer AS w_to
    FROM jsonb_array_elements(:'fold_cases'::jsonb) c;

-- Den 2-arg-krop, der gjaldt før 6d-3 (ordret kopi), som facit for $kilde1_uaendret$.
CREATE OR REPLACE FUNCTION pg_temp.t3_old_windows(p_text text,p_raw text)
RETURNS TABLE(w_from integer,w_to integer) LANGUAGE plpgsql IMMUTABLE STRICT SET search_path=pg_catalog AS $$
DECLARE tw text[]:='{}'; tf int[]:='{}'; tt int[]:='{}'; rw text[]; n int:=0; pos int; mlen int; i int; j int; k int;
  ends int[]:='{}'; starts int[]:='{}';
BEGIN
  LOOP
    pos:=regexp_instr(p_text,'[0-9A-Za-zÀ-ÖØ-öø-ÿ]+',1,n+1);
    EXIT WHEN pos=0;
    mlen:=char_length((regexp_match(substr(p_text,pos),'^[0-9A-Za-zÀ-ÖØ-öø-ÿ]+'))[1]);
    n:=n+1; tw:=tw||lower(substr(p_text,pos,mlen)); tf:=tf||(pos-1); tt:=tt||(pos-1+mlen);
  END LOOP;
  SELECT array_agg(lower(m[1])) INTO rw FROM regexp_matches(p_raw,'([0-9A-Za-zÀ-ÖØ-öø-ÿ]+)','g') m;
  IF rw IS NULL OR n=0 THEN RETURN; END IF;
  FOR i IN 1..n LOOP
    CONTINUE WHEN tw[i]<>rw[1];
    j:=i; k:=2;
    WHILE k<=array_length(rw,1) LOOP
      j:=j+1;
      EXIT WHEN j>n;
      IF tw[j]=rw[k] THEN k:=k+1; END IF;
    END LOOP;
    IF k>array_length(rw,1) THEN starts:=starts||i; ends:=ends||j; END IF;
  END LOOP;
  RETURN QUERY
    SELECT tf[max(u.s)], tt[u.e] FROM unnest(starts,ends) AS u(s,e) GROUP BY u.e ORDER BY 1;
END $$;

-- Ét fixturetilfælde: præcis ét vindue med originalens positioner, eller (null) ikke præcis ét.
CREATE OR REPLACE FUNCTION pg_temp.t3_check(p_like text) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE r record; v_got integer[]; v_n integer:=0;
BEGIN
  FOR r IN SELECT * FROM t3_fold_cases WHERE id LIKE p_like ORDER BY id LOOP
    SELECT array_agg(ARRAY[w.w_from,w.w_to] ORDER BY w.w_from) INTO v_got
      FROM private.relation_ordered_windows(r.text,r.raw,r.text_form) w;
    IF r.w_from IS NULL THEN
      IF coalesce(cardinality(v_got)/2,0)=1 THEN RAISE EXCEPTION 'FOLD_TEST_FAILED: % gav ét vindue %',r.id,v_got; END IF;
    ELSIF v_got IS DISTINCT FROM ARRAY[ARRAY[r.w_from,r.w_to]] THEN
      RAISE EXCEPTION 'FOLD_TEST_FAILED: % forventede [%,%], fik %',r.id,r.w_from,r.w_to,v_got;
    END IF;
    v_n:=v_n+1;
  END LOOP;
  RETURN v_n;
END $$;

DO $fixtur$
BEGIN
  IF (SELECT count(*) FROM t3_fold_cases)<20 OR (SELECT count(DISTINCT id) FROM t3_fold_cases)<>(SELECT count(*) FROM t3_fold_cases)
     OR EXISTS (SELECT 1 FROM t3_fold_cases WHERE text_form NOT IN ('raw','folded') OR text IS NULL OR raw IS NULL
                   OR (w_from IS NULL)<>(w_to IS NULL)) THEN
    RAISE EXCEPTION 'FOLD_TEST_FAILED: fixturen er ufuldstændig';
  END IF;
  RAISE NOTICE 'OK: fixtur (% tilfælde)',(SELECT count(*) FROM t3_fold_cases);
END $fixtur$;

DO $fold_linjeskift$
BEGIN
  IF pg_temp.t3_check('linjeskift%')<3 THEN RAISE EXCEPTION 'FOLD_TEST_FAILED: for få linjeskifttilfælde'; END IF;
  RAISE NOTICE 'OK: linjeskift';
END $fold_linjeskift$;

DO $fold_orddeling$
BEGIN
  IF pg_temp.t3_check('orddeling%')<8 OR pg_temp.t3_check('bindestreg%')<5 THEN
    RAISE EXCEPTION 'FOLD_TEST_FAILED: for få orddelingstilfælde';
  END IF;
  RAISE NOTICE 'OK: orddeling og ægte bindestreg';
END $fold_orddeling$;

DO $fold_sidemarkoer$
BEGIN
  IF pg_temp.t3_check('sidemarkoer%')<8 THEN RAISE EXCEPTION 'FOLD_TEST_FAILED: for få sidemarkørtilfælde'; END IF;
  RAISE NOTICE 'OK: sidemarkør';
END $fold_sidemarkoer$;

DO $fold_alle$
BEGIN
  IF pg_temp.t3_check('%')<>(SELECT count(*) FROM t3_fold_cases) THEN RAISE EXCEPTION 'FOLD_TEST_FAILED: ikke alle tilfælde'; END IF;
  RAISE NOTICE 'OK: alle fixturetilfælde';
END $fold_alle$;

-- 'folded' giver præcis de vinduer, den gamle krop gav — for de eksisterende v2-tilfælde og for alle fixturetekster
-- (også dem med \n, -\n og sidemarkør: 'folded' folder intet). Kilde 1's numre og bindinger kan derfor ikke flytte sig.
DO $kilde1_uaendret$
DECLARE r record;
BEGIN
  IF (SELECT array_agg(ARRAY[w_from,w_to]) FROM private.relation_ordered_windows('Gift 1. gang 1890 med Bo Beta, f. 1801.','gift med Bo Beta','folded'))
     <> ARRAY[ARRAY[0,29]] THEN RAISE EXCEPTION 'FOLD_TEST_FAILED: v2 enkelt vindue'; END IF;
  IF (SELECT count(*) FROM private.relation_ordered_windows('Gift med Åse Ø. Gift med Åse Ø.','gift med åse ø','folded'))<>2 THEN
    RAISE EXCEPTION 'FOLD_TEST_FAILED: v2 to vinduer'; END IF;
  IF (SELECT count(*) FROM private.relation_ordered_windows('Gift med Bo.','gift med Cia','folded'))<>0 THEN
    RAISE EXCEPTION 'FOLD_TEST_FAILED: v2 intet vindue'; END IF;
  IF (SELECT array_agg(ARRAY[w_from,w_to]) FROM private.relation_ordered_windows('g. 2° m. Søren Ærø-Ødegård, f. 1850.','m. søren ødegård','folded'))
     <> ARRAY[ARRAY[6,26]] THEN RAISE EXCEPTION 'FOLD_TEST_FAILED: v2 danske bogstaver'; END IF;
  IF (SELECT array_agg(ARRAY[w_from,w_to]) FROM private.relation_ordered_windows('Gift 1975.','Gift 1975.','folded')) <> ARRAY[ARRAY[0,9]] THEN
    RAISE EXCEPTION 'FOLD_TEST_FAILED: v2 tal som ord'; END IF;
  FOR r IN SELECT text,raw FROM t3_fold_cases
           UNION ALL SELECT * FROM (VALUES ('Gift med Åse Ø. Gift med Åse Ø.','gift med åse ø'),('Gift med Bo.','gift med Cia'),
             ('Gift 1° m. Bo Beta. Gift 2° m. Bo Beta.','m. bo beta'),('','gift'),('Gift.',''),('Gift.','—')) v LOOP
    IF (SELECT array_agg(ARRAY[w_from,w_to] ORDER BY w_from) FROM private.relation_ordered_windows(r.text,r.raw,'folded'))
       IS DISTINCT FROM (SELECT array_agg(ARRAY[w_from,w_to] ORDER BY w_from) FROM pg_temp.t3_old_windows(r.text,r.raw)) THEN
      RAISE EXCEPTION 'FOLD_TEST_FAILED: folded afviger fra den gamle krop for %',r.text;
    END IF;
  END LOOP;
  RAISE NOTICE 'OK: folded uændret';
END $kilde1_uaendret$;

DO $to_arg_indpakning$
DECLARE r record; v_role text;
BEGIN
  FOR r IN SELECT text,raw FROM t3_fold_cases LOOP
    IF (SELECT array_agg(ARRAY[w_from,w_to] ORDER BY w_from) FROM private.relation_ordered_windows(r.text,r.raw))
       IS DISTINCT FROM (SELECT array_agg(ARRAY[w_from,w_to] ORDER BY w_from) FROM private.relation_ordered_windows(r.text,r.raw,'folded')) THEN
      RAISE EXCEPTION 'FOLD_TEST_FAILED: 2-arg <> 3-arg folded for %',r.text;
    END IF;
  END LOOP;
  IF (SELECT array_agg(p.oid::regprocedure::text ORDER BY p.pronargs) FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
       WHERE n.nspname='private' AND p.proname='relation_ordered_windows')
     IS DISTINCT FROM ARRAY['private.relation_ordered_windows(text,text)','private.relation_ordered_windows(text,text,text)'] THEN
    RAISE EXCEPTION 'FOLD_TEST_FAILED: forventede præcis to overloads';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
              WHERE n.nspname='private' AND p.proname='relation_ordered_windows' AND p.pronargdefaults<>0) THEN
    RAISE EXCEPTION 'FOLD_TEST_FAILED: ingen default';
  END IF;
  FOREACH v_role IN ARRAY ARRAY['anon','authenticated','service_role'] LOOP
    IF has_function_privilege(v_role,'private.relation_ordered_windows(text,text)','EXECUTE')
       OR has_function_privilege(v_role,'private.relation_ordered_windows(text,text,text)','EXECUTE')
       OR has_function_privilege(v_role,'private.relation_text_form(bigint)','EXECUTE')
       OR has_function_privilege(v_role,'private.relation_fold_raw_text(text)','EXECUTE') THEN
      RAISE EXCEPTION 'FOLD_TEST_FAILED: % kan kalde foldningen',v_role;
    END IF;
  END LOOP;
  BEGIN
    PERFORM private.relation_ordered_windows('Gift m. Bo.','m. Bo','foldet');
    RAISE EXCEPTION 'FOLD_TEST_FAILED: ukendt tekstform godtaget';
  EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE '%RELATION_TEXT_FORM_INVALID%' THEN RAISE; END IF; END;
  RAISE NOTICE 'OK: 2-arg-indpakning';
END $to_arg_indpakning$;

-- Kildens tekstform: 'raw' når kilden har en raw-profil, ellers 'folded'; aldrig NULL. Blandet (en raw- og en
-- folded-række for samme kilde) giver 'raw': raw-foldningen er identitet på tekst uden linjeskift og sidemarkør, mens
-- 'folded' på rå tekst taber vinduer.
DO $tekstform$
BEGIN
  INSERT INTO public.source(id,slags,titel,udgave,aar) VALUES (-63301,'DAA-udgave','6d-3 fixture','synthetic',1900);
  IF private.relation_text_form(-63301)<>'folded' THEN RAISE EXCEPTION 'FOLD_TEST_FAILED: uden profil'; END IF;
  IF private.relation_text_form(NULL) IS DISTINCT FROM 'folded' THEN RAISE EXCEPTION 'FOLD_TEST_FAILED: NULL-kilde'; END IF;
  PERFORM pg_temp.f5b_relation_profiles(-63301);
  IF private.relation_text_form(-63301)<>'folded' THEN RAISE EXCEPTION 'FOLD_TEST_FAILED: kun folded'; END IF;
  INSERT INTO private.relation_persona_profile(profile,source_id,predicate_forms,text_form)
    VALUES ('relation-persona-fold-test',-63301,'{"relation.marriage":"v3"}','raw');
  IF private.relation_text_form(-63301)<>'raw' THEN RAISE EXCEPTION 'FOLD_TEST_FAILED: blandet'; END IF;
  DELETE FROM private.relation_persona_profile WHERE source_id=-63301 AND text_form='folded';
  IF private.relation_text_form(-63301)<>'raw' THEN RAISE EXCEPTION 'FOLD_TEST_FAILED: kun raw'; END IF;
  RAISE NOTICE 'OK: kildens tekstform';
END $tekstform$;
ROLLBACK;

-- Review Focus 1: en post med tre ægteskaber, hvor det første står over en orddeling og det andet over en sidemarkør.
-- På en raw-kilde følger numrene teksten (1, 2, 3); på en folded-kilde (kontrol) får de to første ingen position og
-- sorteres sidst, som før 6d-3.
BEGIN;
\ir fixtures/relation-5b.sql
DO $fold_ordinal_blandet$
DECLARE v_actor uuid:='11000000-0000-0000-0000-000000633101'; v_src bigint; s jsonb; p jsonb; c1 jsonb; c2 jsonb; c3 jsonb;
  v_ord int[]; v_off int[]; v_clauses text[]:=ARRAY['Åse Alfa, f. 1801.',
    E'Gift 1° m. Karl Bran-\ndenburg, f. 1795.',E'Gift 2° m. Bo Be-\n\n### PAGE 0011 ###\nta, f. 1790.','Gift 3° m. Cai Ceta, f. 1799.'];
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) SELECT g,false,false,'6d3' FROM generate_series(-63312,-63311) g;
  FOREACH v_src IN ARRAY ARRAY[-63311,-63312]::bigint[] LOOP
    s:=pg_temp.f5b_source(v_src);
    IF v_src=-63311 THEN
      UPDATE private.relation_persona_profile SET text_form='raw' WHERE source_id=v_src;
    END IF;
    p:=pg_temp.f5b_post(v_src,s,'F-1',array_to_string(v_clauses,' '),v_clauses,v_src,v_actor);
    -- Påstandene oprettes i omvendt rækkefølge, så nøgle- og oprettelsesorden ikke kan forklare resultatet.
    c3:=pg_temp.f5b_claim(v_src,s,'relation.marriage',(p->'clauses'->>3)::uuid,'Gift 3° m. Cai Ceta, f. 1799');
    c2:=pg_temp.f5b_claim(v_src,s,'relation.marriage',(p->'clauses'->>2)::uuid,'Gift 2° m. Bo Beta, f. 1790');
    c1:=pg_temp.f5b_claim(v_src,s,'relation.marriage',(p->'clauses'->>1)::uuid,'Gift 1° m. Karl Brandenburg, f. 1795');
    SELECT array_agg(o.marriage_ordinal ORDER BY k.n),array_agg(o.post_offset ORDER BY k.n) INTO v_ord,v_off
      FROM private.relation_marriage_ordinals((p->>'occ')::uuid) o
      JOIN (VALUES ((c1->>'key')::uuid,1),((c2->>'key')::uuid,2),((c3->>'key')::uuid,3)) k(key,n) ON k.key=o.interpretation_key;
    IF v_src=-63311 THEN
      IF v_ord IS DISTINCT FROM ARRAY[1,2,3] THEN RAISE EXCEPTION 'FOLD_TEST_FAILED: raw-numre %',v_ord; END IF;
      IF v_off IS DISTINCT FROM (SELECT array_agg(post_char_from ORDER BY clause_ordinal) FROM private.source_observation
                                  WHERE parent_observation_id=(p->>'helpost')::uuid AND clause_ordinal>1) THEN
        RAISE EXCEPTION 'FOLD_TEST_FAILED: raw-positioner %',v_off;
      END IF;
    -- Kontrol: uden foldning har de to første intet vindue; det tredje bliver nr. 1, de to andre sorteres efter længde.
    ELSIF v_ord IS DISTINCT FROM ARRAY[3,2,1] OR v_off[1] IS NOT NULL OR v_off[2] IS NOT NULL OR v_off[3] IS NULL THEN
      RAISE EXCEPTION 'FOLD_TEST_FAILED: folded-kontrol % %',v_ord,v_off;
    END IF;
  END LOOP;
  RAISE NOTICE 'OK: ægteskabsnummer følger teksten på en raw-kilde';
END $fold_ordinal_blandet$;
ROLLBACK;

-- Writerens spændtjek bruger kildens tekstform: samme v2-payload med originalens vindue over en orddeling skrives på en
-- raw-kilde og afvises på en folded-kilde. Ægtefællens mention er originalens tekst (med orddelingen).
BEGIN;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
DO $fold_writer_spaend$
DECLARE v_actor uuid:='11000000-0000-0000-0000-000000633201'; v_src bigint; s jsonb; p jsonb; c jsonb; v_clause uuid; e jsonb;
  v_text text:=E'Gift 1890 med Bo Bran-\ndenburg, f. 1801.';
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) SELECT g,false,false,'6d3' FROM generate_series(-63322,-63321) g;
  FOREACH v_src IN ARRAY ARRAY[-63321,-63322]::bigint[] LOOP
    s:=pg_temp.f5b_source(v_src);
    IF v_src=-63321 THEN UPDATE private.relation_persona_profile SET text_form='raw' WHERE source_id=v_src; END IF;
    p:=pg_temp.f5b_post(v_src,s,'W-1','Ida Iota. '||v_text,ARRAY['Ida Iota.',v_text],v_src,v_actor);
    PERFORM pg_temp.f2a_event_for_state((p->>'principal')::uuid);
    v_clause:=(p->'clauses'->>1)::uuid;
    c:=pg_temp.f5b_claim(v_src,s,'relation.marriage',v_clause,'Gift med Bo Brandenburg.');
    e:=jsonb_build_object('birth_raw',NULL,'clause_observation_id',v_clause,'clause_set_seq',1,
      'clause_set_sha256',private.clause_set_sha256((p->>'helpost')::uuid,1),'death_raw',NULL,
      'interpretation_key',c->>'key','interpretation_version',1,'marriage_ordinal',1,
      'name_from',14,'name_to',30,'post_offset',(SELECT post_char_from FROM private.source_observation WHERE id=v_clause),
      'predicate','relation.marriage','profile','relation-persona-2018-20-v2','span_from',0,'span_to',30);
    IF v_src=-63321 THEN
      PERFORM pg_temp.f5b_write(v_src,v_actor,jsonb_build_object('relation-persona:'||(c->>'key'),e));
      IF (SELECT sm.verbatim_text FROM private.interpretation_party_current pc
            JOIN private.source_persona_mention spm ON spm.persona_id=pc.source_persona_id AND spm.mention_role='spouse'
            JOIN private.source_mention sm ON sm.id=spm.mention_id
           WHERE pc.interpretation_key=(c->>'key')::uuid AND pc.party_role='spouse') IS DISTINCT FROM E'Bo Bran-\ndenburg' THEN
        RAISE EXCEPTION 'FOLD_TEST_FAILED: ægtefælle-mention på raw-kilde';
      END IF;
    ELSE
      BEGIN
        PERFORM pg_temp.f5b_write(v_src,v_actor,jsonb_build_object('relation-persona:'||(c->>'key'),e));
        RAISE EXCEPTION 'FOLD_TEST_FAILED: orddelt vindue godtaget på folded-kilde';
      EXCEPTION WHEN raise_exception THEN IF SQLERRM NOT LIKE '%RELATION_PERSONA_SPAN_INVALID%' THEN RAISE; END IF; END;
    END IF;
  END LOOP;
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;   -- udskudte identitetstjek må ikke skjules af ROLLBACK
  RAISE NOTICE 'OK: writerens spændtjek følger kildens tekstform';
END $fold_writer_spaend$;
ROLLBACK;

-- Codex-fund (6d-3 Task 3): et mention-navn over en sidemarkør sendes foldet til kandidatmatcheren på en raw-kilde, og
-- værdien er den samme som den rene tekst giver; på en folded-kilde er navnet ordret som før (kilde 1 uændret).
BEGIN;
\ir fixtures/relation-5b.sql
DO $fold_kandidatinput$
DECLARE v_actor uuid:='11000000-0000-0000-0000-000000633301'; v_src bigint; s jsonb; p jsonb; c jsonb; v_persona uuid;
  v_name text:='Bo Be-'||chr(10)||chr(10)||'### PAGE 0011 ###'||chr(10)||'ta'; v_clause text; v_in jsonb; v_clean jsonb;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  PERFORM set_config('request.jwt.claim.sub',v_actor::text,true);
  v_clause:='Gift 2° m. '||v_name||', f. 1790.';
  INSERT INTO person(id,levende,privat,status) SELECT g,false,false,'6d3' FROM generate_series(-63333,-63331) g;
  FOREACH v_src IN ARRAY ARRAY[-63331,-63332,-63333]::bigint[] LOOP
    s:=pg_temp.f5b_source(v_src);
    IF v_src=-63331 THEN UPDATE private.relation_persona_profile SET text_form='raw' WHERE source_id=v_src; END IF;
    -- -63333 er kontrollen: samme post med den rene tekst på en folded-kilde.
    IF v_src=-63333 THEN v_clause:='Gift 2° m. Bo Beta, f. 1790.'; END IF;
    p:=pg_temp.f5b_post(v_src,s,'K-1','Eva Epsilon. '||v_clause,ARRAY['Eva Epsilon.',v_clause],v_src,v_actor);
    c:=pg_temp.f5b_claim(v_src,s,'relation.marriage',(p->'clauses'->>1)::uuid,'Gift 2° m. Bo Beta, f. 1790');
    v_persona:=pg_temp.f5b_spouse(v_src,s,p,c,(p->'clauses'->>1)::uuid,CASE WHEN v_src=-63333 THEN 'Bo Beta' ELSE v_name END,1);
    v_in:=private.identity_candidate_input(v_src,jsonb_build_object('mode','list','persona_ids',jsonb_build_array(v_persona)));
    IF v_in#>>'{personas,0,name_origin}'<>'mention' THEN RAISE EXCEPTION 'FOLD_TEST_FAILED: navnets oprindelse %',v_in; END IF;
    IF v_src=-63331 AND v_in#>>'{personas,0,name}'<>'Bo Beta' THEN
      RAISE EXCEPTION 'FOLD_TEST_FAILED: raw-kildens kandidatnavn %',v_in#>>'{personas,0,name}';
    ELSIF v_src=-63332 AND v_in#>>'{personas,0,name}'<>v_name THEN
      RAISE EXCEPTION 'FOLD_TEST_FAILED: folded-kildens kandidatnavn er ikke ordret';
    ELSIF v_src=-63333 THEN
      v_clean:=v_in;
    END IF;
    -- Mentionen selv er ordret med originalens positioner.
    IF (SELECT sm.verbatim_text FROM private.source_persona_mention spm JOIN private.source_mention sm ON sm.id=spm.mention_id
         WHERE spm.persona_id=v_persona) IS DISTINCT FROM (CASE WHEN v_src=-63333 THEN 'Bo Beta' ELSE v_name END) THEN
      RAISE EXCEPTION 'FOLD_TEST_FAILED: mentionen er ikke ordret';
    END IF;
  END LOOP;
  IF v_clean#>>'{personas,0,name}'<>'Bo Beta' THEN RAISE EXCEPTION 'FOLD_TEST_FAILED: kontrollens navn'; END IF;
  -- Sammenligningsformen: identitet på folded-kilder og for tekst uden skift; NULL bevares.
  IF private.relation_name_compare_text(-63332,v_name)<>v_name OR private.relation_name_compare_text(-63331,'Bo  Beta')<>'Bo  Beta'
     OR private.relation_name_compare_text(-63331,NULL) IS NOT NULL OR private.relation_name_compare_text(NULL,v_name)<>v_name THEN
    RAISE EXCEPTION 'FOLD_TEST_FAILED: relation_name_compare_text';
  END IF;
  RAISE NOTICE 'OK: kandidatinputtet folder mention-navnet på en raw-kilde';
END $fold_kandidatinput$;
ROLLBACK;

-- Codex-fund (6d-3 Task 3): genbrug efter en tekstrevision, der fjerner en orddeling i ægtefællens navn. På en raw-kilde
-- er »Bo Bran-\ndenburg« og »Bo Brandenburg« samme navn, så writeren genbruger personaen, og finalize
-- (verify_relation_persona_receipts) godtager kvitteringen. Kontrol: samme forløb på en folded-kilde opretter en ny
-- persona, som før 6d-3.
BEGIN ISOLATION LEVEL READ COMMITTED;
\ir fixtures/relation-5b.sql
\ir fixtures/relation-2a.sql
\ir fixtures/source-text-revision.sql
\ir fixtures/relation-persona-reuse-helpers.sql
CREATE OR REPLACE FUNCTION pg_temp.t3_bind(p_source bigint,p_principal bigint,p_spouse_person bigint,p_persona uuid,p_key text,
  p_actor uuid) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v_at timestamptz:=clock_timestamp(); v_fam bigint; pv jsonb; items jsonb;
BEGIN
  INSERT INTO private.source_persona_identity_event(source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at)
    VALUES (p_persona,p_spouse_person,'accepted',1,'{"fixture":"6d3"}',p_actor,'fixture',v_at);
  INSERT INTO private.source_persona_identity(source_persona_id,canonical_person_id,decision_status,version,evidence,
    decided_by,decided_by_name,decided_at)
    VALUES (p_persona,p_spouse_person,'accepted',1,'{"fixture":"6d3"}',p_actor,'fixture',v_at);
  v_fam:=pg_temp.f5b_family(p_principal,p_spouse_person,1);
  PERFORM set_config('request.jwt.claim.sub',p_actor::text,true);
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_decisions(p_source);
  PERFORM red_decide_relation_interpretations(p_source,pv->>'set_sha256');
  RESET ROLE;
  SELECT jsonb_agg(jsonb_build_object('interpretation_id',ic.id::text,'family_id',v_fam)) INTO items
    FROM private.interpretation_current ic WHERE ic.interpretation_key=p_key::uuid AND ic.status='accepted';
  IF items IS NULL THEN RAISE EXCEPTION 'T3_BIND_NOT_ACCEPTED'; END IF;
  SET LOCAL ROLE authenticated;
  pv:=red_preview_relation_promotions(p_source,items);
  PERFORM red_promote_relation_interpretations_batch(p_source,items,pv->>'preview_sha256');
  RESET ROLE;
  RETURN v_fam;
END $$;
CREATE OR REPLACE FUNCTION pg_temp.t3_revise(p_source bigint,p_post jsonb,p_old text,p_new text,p_parts text[],p_actor uuid,p_nonce text)
RETURNS uuid[] LANGUAGE plpgsql AS $$
DECLARE fx jsonb; r jsonb;
BEGIN
  fx:=jsonb_build_object('source',p_source,'record_key',p_post->>'key','helpost',p_post->>'helpost','text',p_old,
    'actor',p_actor,'profile',pg_temp.t5_profile(p_source));
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  r:=pg_temp.t5_apply(fx,pg_temp.t5_payload(fx,p_new,p_parts),p_nonce);
  SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
  IF jsonb_array_length(r->'superseded_keys')=0 THEN RAISE EXCEPTION 'T3_REVISION_SUPERSEDED_NOTHING'; END IF;
  RETURN ARRAY(SELECT id FROM private.clause_observation_current WHERE parent_observation_id=(p_post->>'helpost')::uuid
                ORDER BY clause_ordinal);
END $$;
DO $fold_genbrug$
DECLARE v_actor uuid:='11000000-0000-0000-0000-000000633401'; v_src bigint; s jsonb; post jsonb; c jsonb; c2 jsonb; p jsonb;
  w jsonb; v_persona uuid; v_cl uuid[]; v_n bigint; v_old_clause text:='Gift med Bo Bran-'||chr(10)||'denburg.';
  v_old text; v_new text:='Anna Alfa. Gift med Bo Brandenburg.';
BEGIN
  v_old:='Anna Alfa. '||v_old_clause;
  PERFORM pg_temp.f5b_actor(v_actor);
  INSERT INTO person(id,levende,privat,status) SELECT g,false,false,'6d3' FROM generate_series(-63344,-63341) g;
  FOREACH v_src IN ARRAY ARRAY[-63341,-63343]::bigint[] LOOP
    s:=pg_temp.f5b_source(v_src);
    IF v_src=-63341 THEN UPDATE private.relation_persona_profile SET text_form='raw' WHERE source_id=v_src; END IF;
    post:=pg_temp.f5b_post(v_src,s,'G-1',v_old,ARRAY['Anna Alfa.',v_old_clause],v_src,v_actor);
    PERFORM pg_temp.f2a_event_for_state((post->>'principal')::uuid);
    c:=pg_temp.f5b_claim(v_src,s,'relation.marriage',(post->'clauses'->>1)::uuid,v_old_clause);
    PERFORM pg_temp.t6_write(v_src,v_actor,pg_temp.t6_payload((post->'clauses'->>1)::uuid,c->>'key',v_old_clause,
                                                               'Bo Bran-'||chr(10)||'denburg'));
    v_persona:=pg_temp.t6_spouse(c->>'key');
    PERFORM pg_temp.t3_bind(v_src,v_src,v_src-1,v_persona,c->>'key',v_actor);
    SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
    v_cl:=pg_temp.t3_revise(v_src,post,v_old,v_new,ARRAY['Anna Alfa.','Gift med Bo Brandenburg.'],v_actor,'t3-'||abs(v_src));
    c2:=pg_temp.f5b_claim(v_src,s,'relation.marriage',v_cl[2],'Gift med Bo Brandenburg.');
    SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
    v_n:=(SELECT count(*) FROM private.source_persona WHERE source_id=v_src);
    w:=pg_temp.t6_write(v_src,v_actor,pg_temp.t6_payload(v_cl[2],c2->>'key','Gift med Bo Brandenburg.','Bo Brandenburg'));
    SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;
    IF (SELECT status FROM private.reimport_batch WHERE id=(w->>'batch')::uuid)<>'finalized' THEN
      RAISE EXCEPTION 'FOLD_TEST_FAILED: batchen er ikke finaliseret (%)',v_src;
    END IF;
    IF v_src=-63341 THEN
      IF pg_temp.t6_spouse(c2->>'key') IS DISTINCT FROM v_persona OR w->'receipt'->'reused'<>'true'::jsonb
         OR (SELECT count(*) FROM private.source_persona WHERE source_id=v_src)<>v_n THEN
        RAISE EXCEPTION 'FOLD_TEST_FAILED: raw-kilden genbrugte ikke personaen (%)',w->'receipt';
      END IF;
    ELSIF pg_temp.t6_spouse(c2->>'key') IS NOT DISTINCT FROM v_persona OR w->'receipt' ? 'reused'
          OR (SELECT count(*) FROM private.source_persona WHERE source_id=v_src)<>v_n+1 THEN
      RAISE EXCEPTION 'FOLD_TEST_FAILED: folded-kontrollen genbrugte (%)',w->'receipt';
    END IF;
  END LOOP;
  RAISE NOTICE 'OK: genbrug efter fjernet orddeling på en raw-kilde (finalize grøn); folded-kontrol uændret';
END $fold_genbrug$;
ROLLBACK;
