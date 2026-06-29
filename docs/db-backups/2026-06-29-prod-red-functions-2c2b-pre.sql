-- PROD-BACKUP red_* før 2C-2b-deploy
CREATE OR REPLACE FUNCTION public.red_edit_oplysning(p_assertion_id bigint, p_vaerdi text, p_date_raw text DEFAULT NULL::text, p_kilde_fritekst text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  UPDATE assertion SET vaerdi_tekst = p_vaerdi,
                       date_raw = coalesce(p_date_raw, date_raw)
    WHERE id = p_assertion_id;
  IF p_kilde_fritekst IS NOT NULL THEN
    UPDATE citation SET citat_tekst = p_kilde_fritekst WHERE assertion_id = p_assertion_id;
  END IF;
END $function$
;
CREATE OR REPLACE FUNCTION public.red_opret_fakta(p_subjekt_type text, p_subjekt_id bigint, p_faktatype text, p_vaerdi text, p_date_min date DEFAULT NULL::date, p_date_max date DEFAULT NULL::date, p_date_qualifier text DEFAULT NULL::text, p_date_raw text DEFAULT NULL::text, p_kilde_fritekst text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_fact bigint; v_assert bigint; v_cit bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  INSERT INTO fact(id, subjekt_type, subjekt_id, faktatype)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM fact), p_subjekt_type, p_subjekt_id, p_faktatype)
    RETURNING id INTO v_fact;
  INSERT INTO assertion(id, target_type, target_id, vaerdi_tekst,
                        date_min, date_max, date_qualifier, date_raw, uforanderlig)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM assertion), 'fact', v_fact, p_vaerdi,
            p_date_min, p_date_max, p_date_qualifier, p_date_raw, false)
    RETURNING id INTO v_assert;
  INSERT INTO citation(id, assertion_id, source_id, citat_tekst)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM citation), v_assert, NULL,
            coalesce(p_kilde_fritekst,'(kilde mangler)'))
    RETURNING id INTO v_cit;
  INSERT INTO conclusion(id, target_type, target_id, valgt_assertion_id, status, blaastemplet_af, blaastemplet_naar)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM conclusion), 'fact', v_fact, v_assert,
            'afklaret', 'Redaktør', current_date);
  RETURN jsonb_build_object('fact_id', v_fact, 'assertion_id', v_assert, 'citation_id', v_cit);
END $function$
;
CREATE OR REPLACE FUNCTION public.red_relation(p_subjekt_type text, p_subjekt_id bigint, p_objekt_type text, p_objekt_id bigint, p_rolle text, p_periode_raw text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_id bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  INSERT INTO relation(id, subjekt_type, subjekt_id, objekt_type, objekt_id, rolle, periode_raw)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM relation),
            p_subjekt_type, p_subjekt_id, p_objekt_type, p_objekt_id, p_rolle, p_periode_raw)
    RETURNING id INTO v_id;
  RETURN v_id;
END $function$
;
CREATE OR REPLACE FUNCTION public.red_set_koen(p_person_id bigint, p_koen text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  UPDATE person SET koen = p_koen WHERE id = p_person_id;  -- CHECK håndhæver vokabular
END $function$
;
CREATE OR REPLACE FUNCTION public.red_set_konklusion(p_assertion_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_target_type text; v_target_id bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  SELECT target_type, target_id INTO v_target_type, v_target_id FROM assertion WHERE id = p_assertion_id;
  IF v_target_id IS NULL THEN RAISE EXCEPTION 'Ukendt assertion %', p_assertion_id; END IF;
  INSERT INTO conclusion(id, target_type, target_id, valgt_assertion_id, status, blaastemplet_af, blaastemplet_naar)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM conclusion), v_target_type, v_target_id, p_assertion_id,
            'afklaret', 'Redaktør', current_date)
    ON CONFLICT (target_type, target_id)
    DO UPDATE SET valgt_assertion_id = excluded.valgt_assertion_id, blaastemplet_naar = current_date;
END $function$
;
CREATE OR REPLACE FUNCTION public.red_set_privat(p_person_id bigint, p_privat boolean)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  UPDATE person SET privat = p_privat WHERE id = p_person_id;
END $function$
;
CREATE OR REPLACE FUNCTION public.red_slet_oplysning(p_assertion_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_target_type text; v_target_id bigint; v_was_chosen boolean; v_next bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  SELECT target_type, target_id INTO v_target_type, v_target_id FROM assertion WHERE id = p_assertion_id;
  IF v_target_id IS NULL THEN RETURN; END IF;
  SELECT (valgt_assertion_id = p_assertion_id) INTO v_was_chosen
    FROM conclusion WHERE target_type=v_target_type AND target_id=v_target_id;
  IF coalesce(v_was_chosen,false) THEN
    SELECT id INTO v_next FROM assertion
      WHERE target_type=v_target_type AND target_id=v_target_id AND id <> p_assertion_id ORDER BY id LIMIT 1;
    IF v_next IS NULL THEN DELETE FROM conclusion WHERE target_type=v_target_type AND target_id=v_target_id;
    ELSE UPDATE conclusion SET valgt_assertion_id=v_next WHERE target_type=v_target_type AND target_id=v_target_id; END IF;
  END IF;
  DELETE FROM citation  WHERE assertion_id = p_assertion_id;
  DELETE FROM assertion WHERE id = p_assertion_id;
END $function$
;
CREATE OR REPLACE FUNCTION public.red_slet_person(p_person_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_facts bigint[]; v_rels bigint[];
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  SELECT coalesce(array_agg(id),'{}') INTO v_facts FROM fact WHERE subjekt_type='person' AND subjekt_id=p_person_id;
  SELECT coalesce(array_agg(id),'{}') INTO v_rels FROM relation
    WHERE (subjekt_type='person' AND subjekt_id=p_person_id) OR (objekt_type='person' AND objekt_id=p_person_id);
  UPDATE profiles SET reventlow_person_id = NULL WHERE reventlow_person_id = p_person_id;
  DELETE FROM citation WHERE assertion_id IN (
    SELECT id FROM assertion WHERE (target_type='fact' AND target_id = ANY(v_facts))
                                OR (target_type='relation' AND target_id = ANY(v_rels)));
  DELETE FROM conclusion WHERE (target_type='fact' AND target_id = ANY(v_facts)) OR (target_type='relation' AND target_id = ANY(v_rels));
  DELETE FROM assertion  WHERE (target_type='fact' AND target_id = ANY(v_facts)) OR (target_type='relation' AND target_id = ANY(v_rels));
  DELETE FROM note WHERE (target_type='person' AND target_id=p_person_id)
                      OR (target_type='fact' AND target_id = ANY(v_facts)) OR (target_type='relation' AND target_id = ANY(v_rels));
  DELETE FROM narrative          WHERE subjekt_type='person' AND subjekt_id=p_person_id;
  DELETE FROM relation           WHERE id = ANY(v_rels);
  DELETE FROM fact               WHERE id = ANY(v_facts);
  DELETE FROM person_external_id WHERE person_id = p_person_id;
  DELETE FROM family_member      WHERE person_id = p_person_id;
  DELETE FROM person             WHERE id = p_person_id;
END $function$
;
CREATE OR REPLACE FUNCTION public.red_slet_person_preview(p_person_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_rels jsonb; v_nfacts int;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  SELECT count(*) INTO v_nfacts FROM fact
    WHERE subjekt_type='person' AND subjekt_id=p_person_id;
  SELECT coalesce(jsonb_agg(r), '[]'::jsonb) INTO v_rels FROM (
    SELECT rolle,
           CASE WHEN subjekt_type='person' AND subjekt_id=p_person_id
                THEN 'ud' ELSE 'ind' END AS retning,
           CASE WHEN subjekt_type='person' AND subjekt_id=p_person_id
                THEN objekt_id ELSE subjekt_id END AS modpart_id
    FROM relation
    WHERE (subjekt_type='person' AND subjekt_id=p_person_id)
       OR (objekt_type='person'  AND objekt_id=p_person_id)
  ) r;
  RETURN jsonb_build_object(
    'antal_relationer', jsonb_array_length(v_rels),
    'antal_facts', v_nfacts,
    'relationer', v_rels);
END $function$
;
CREATE OR REPLACE FUNCTION public.red_slet_relation(p_relation_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  DELETE FROM citation WHERE assertion_id IN
    (SELECT id FROM assertion WHERE target_type='relation' AND target_id=p_relation_id);
  DELETE FROM conclusion WHERE target_type='relation' AND target_id=p_relation_id;
  DELETE FROM assertion  WHERE target_type='relation' AND target_id=p_relation_id;
  DELETE FROM note       WHERE target_type='relation' AND target_id=p_relation_id;
  DELETE FROM relation   WHERE id=p_relation_id;
END $function$
;
CREATE OR REPLACE FUNCTION public.red_suggest(p_art text, p_subjekt_type text, p_subjekt_id bigint, p_felt text, p_vaerdi text, p_kilde_fritekst text DEFAULT NULL::text, p_payload jsonb DEFAULT '{}'::jsonb, p_note text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_id bigint;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Login kræves for forslag'; END IF;
  INSERT INTO suggestion(forslagsstiller, art, subjekt_type, subjekt_id, felt, vaerdi,
                         kilde_fritekst, payload, note)
    VALUES (auth.uid(), p_art, p_subjekt_type, p_subjekt_id, p_felt, p_vaerdi,
            p_kilde_fritekst, coalesce(p_payload,'{}'::jsonb), p_note)
    RETURNING id INTO v_id;
  RETURN v_id;
END $function$
;
CREATE OR REPLACE FUNCTION public.red_tilfoej_oplysning(p_fact_id bigint, p_vaerdi text, p_date_min date DEFAULT NULL::date, p_date_max date DEFAULT NULL::date, p_date_qualifier text DEFAULT NULL::text, p_date_raw text DEFAULT NULL::text, p_kilde_fritekst text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_assert bigint; v_cit bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF NOT EXISTS (SELECT 1 FROM fact WHERE id = p_fact_id) THEN
    RAISE EXCEPTION 'Fact % findes ikke', p_fact_id;
  END IF;
  INSERT INTO assertion(id, target_type, target_id, vaerdi_tekst,
                        date_min, date_max, date_qualifier, date_raw, uforanderlig)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM assertion), 'fact', p_fact_id, p_vaerdi,
            p_date_min, p_date_max, p_date_qualifier, p_date_raw, false)
    RETURNING id INTO v_assert;
  INSERT INTO citation(id, assertion_id, source_id, citat_tekst)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM citation), v_assert, NULL,
            coalesce(p_kilde_fritekst,'(kilde mangler)'))
    RETURNING id INTO v_cit;
  RETURN jsonb_build_object('assertion_id', v_assert, 'citation_id', v_cit);
END $function$
;
CREATE OR REPLACE FUNCTION public.red_tilfoej_relation(p_subjekt_id bigint, p_objekt_type text, p_objekt_id bigint, p_rolle text, p_periode_raw text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_id bigint; v_findes boolean;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF NOT EXISTS(SELECT 1 FROM person WHERE id=p_subjekt_id) THEN RAISE EXCEPTION 'Person % findes ikke', p_subjekt_id; END IF;
  IF p_objekt_type NOT IN ('organisation','estate') THEN RAISE EXCEPTION 'Ugyldig objekt_type %', p_objekt_type; END IF;
  IF p_objekt_type='organisation' THEN SELECT EXISTS(SELECT 1 FROM organisation WHERE id=p_objekt_id) INTO v_findes;
  ELSE SELECT EXISTS(SELECT 1 FROM estate WHERE id=p_objekt_id) INTO v_findes; END IF;
  IF NOT v_findes THEN RAISE EXCEPTION 'Objekt %/% findes ikke', p_objekt_type, p_objekt_id; END IF;
  SELECT id INTO v_id FROM relation WHERE subjekt_type='person' AND subjekt_id=p_subjekt_id
    AND objekt_type=p_objekt_type AND objekt_id=p_objekt_id AND coalesce(rolle,'')=coalesce(p_rolle,'') LIMIT 1;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;
  INSERT INTO relation(id, subjekt_type, subjekt_id, objekt_type, objekt_id, rolle, periode_raw)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM relation), 'person', p_subjekt_id, p_objekt_type, p_objekt_id, p_rolle, p_periode_raw)
    RETURNING id INTO v_id;
  RETURN v_id;
END $function$
;
CREATE OR REPLACE FUNCTION public.red_upsert_fakta(p_subjekt_type text, p_subjekt_id bigint, p_faktatype text, p_vaerdi text, p_date_min date DEFAULT NULL::date, p_date_max date DEFAULT NULL::date, p_date_qualifier text DEFAULT NULL::text, p_date_raw text DEFAULT NULL::text, p_kilde_fritekst text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_fact bigint; v_assert bigint; v_cit bigint; v_concl bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN
    RAISE EXCEPTION 'Kun redaktion må skrive fakta (din rolle: %)', current_rolle();
  END IF;

  SELECT id INTO v_fact FROM fact
    WHERE subjekt_type=p_subjekt_type AND subjekt_id=p_subjekt_id AND faktatype=p_faktatype
    LIMIT 1;
  IF v_fact IS NULL THEN
    INSERT INTO fact(id, subjekt_type, subjekt_id, faktatype)
      VALUES ((SELECT coalesce(max(id),0)+1 FROM fact), p_subjekt_type, p_subjekt_id, p_faktatype)
      RETURNING id INTO v_fact;
  END IF;

  INSERT INTO assertion(id, target_type, target_id, vaerdi_tekst,
                        date_min, date_max, date_qualifier, date_raw, uforanderlig)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM assertion), 'fact', v_fact, p_vaerdi,
            p_date_min, p_date_max, p_date_qualifier, p_date_raw, false)
    RETURNING id INTO v_assert;

  INSERT INTO citation(id, assertion_id, source_id, citat_tekst)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM citation), v_assert, NULL,
            coalesce(p_kilde_fritekst,'(kilde mangler)'))
    RETURNING id INTO v_cit;

  INSERT INTO conclusion(id, target_type, target_id, valgt_assertion_id, status, blaastemplet_af, blaastemplet_naar)
    VALUES ((SELECT coalesce(max(id),0)+1 FROM conclusion), 'fact', v_fact, v_assert,
            'afklaret', 'Redaktør', current_date)
    ON CONFLICT (target_type, target_id)
    DO UPDATE SET valgt_assertion_id=excluded.valgt_assertion_id, status='afklaret',
                  blaastemplet_af='Redaktør', blaastemplet_naar=current_date
    RETURNING id INTO v_concl;

  RETURN jsonb_build_object('fact_id',v_fact,'assertion_id',v_assert,
                            'citation_id',v_cit,'conclusion_id',v_concl);
END $function$
;
CREATE OR REPLACE FUNCTION public.red_upsert_narrativ(p_subjekt_type text, p_subjekt_id bigint, p_tekst text, p_privat boolean DEFAULT false)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_id bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  SELECT id INTO v_id FROM narrative
    WHERE subjekt_type=p_subjekt_type AND subjekt_id=p_subjekt_id ORDER BY id LIMIT 1;
  IF v_id IS NULL THEN
    INSERT INTO narrative(id, subjekt_type, subjekt_id, tekst, privat)
      VALUES ((SELECT coalesce(max(id),0)+1 FROM narrative), p_subjekt_type, p_subjekt_id, p_tekst, p_privat)
      RETURNING id INTO v_id;
  ELSE
    UPDATE narrative SET tekst=p_tekst, privat=p_privat WHERE id=v_id;
  END IF;
  RETURN v_id;
END $function$
;
