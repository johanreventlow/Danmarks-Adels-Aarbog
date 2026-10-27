-- #150 trin 5c-1: delte fixtures for placement, ledger og membership. Kræver fixtures/relation-5b.sql (\ir først).
-- Alt oprettes i den kaldende transaktion og rulles tilbage af testen. Kald dem som ejer, før SET LOCAL ROLE.

-- Kilde med slægt, linje, stamtavle-schema (entry 'I' → linjen, canonical), header-kørsel og redaktør-aktør.
CREATE OR REPLACE FUNCTION pg_temp.f150_source(p_source bigint) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_actor uuid:='a1500000-0000-0000-0000-000000000150'; v_src jsonb; v_slaegt bigint; v_lineage bigint;
  v_scheme bigint; v_entry bigint;
BEGIN
  PERFORM pg_temp.f5b_actor(v_actor);
  v_src:=pg_temp.f5b_source(p_source);
  INSERT INTO public.slaegt(navn,sorteringsnavn,slug,status)
    VALUES ('150 fixture '||p_source,'150 fixture '||p_source,'f150-'||abs(p_source),'historical') RETURNING id INTO v_slaegt;
  INSERT INTO public.lineage(slaegt_id,canonical_label,navn) VALUES (v_slaegt,'I. linje','150 fixture linje')
    RETURNING id INTO v_lineage;
  INSERT INTO public.lineage_scheme(slaegt_id,source_id,kind,label) VALUES (v_slaegt,p_source,'stamtavle','150 fixture')
    RETURNING id INTO v_scheme;
  INSERT INTO public.lineage_scheme_entry(scheme_id,slaegt_id,code,label,sort_order)
    VALUES (v_scheme,v_slaegt,'I','I. linje',1) RETURNING id INTO v_entry;
  INSERT INTO public.lineage_scheme_entry_lineage(entry_id,lineage_id,slaegt_id,relation_kind)
    VALUES (v_entry,v_lineage,v_slaegt,'canonical');
  RETURN v_src||jsonb_build_object('source',p_source,'slaegt',v_slaegt,'lineage',v_lineage,'entry',v_entry,'actor',v_actor);
END $$;

-- Hovedperson-post (forekomst ved tegn 1000 som f5b_post) med person, legacy-række og accepteret identitet.
CREATE OR REPLACE FUNCTION pg_temp.f150_post(f jsonb,p_key text,p_person bigint,p_nr int,p_slaegtled int)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_post jsonb;
BEGIN
  INSERT INTO public.person(id) VALUES (p_person) ON CONFLICT DO NOTHING;
  v_post:=pg_temp.f5b_post((f->>'source')::bigint,f,p_key,'Opdigtet Testesen, f. 1600.',ARRAY['Opdigtet Testesen'],
    p_person,(f->>'actor')::uuid);
  INSERT INTO public.person_external_id(person_id,source_id,linje,nr,record_key,slaegtled_lokal)
    VALUES (p_person,(f->>'source')::bigint,'I',p_nr,p_key,p_slaegtled);
  RETURN v_post||jsonb_build_object('person',p_person);
END $$;

-- Header-kørslens parametre og ét manifest-element (som build_header_manifest.py).
CREATE OR REPLACE FUNCTION pg_temp.f150_run() RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('run_key','header-2018-20-v1','schema_version','header-manifest-v1',
    'extractor_version','build_header_manifest.py','profile_version','header-2018-20-v1','input_sha256',repeat('9',64),
    'manifest',jsonb_build_object('manifest_sha256',repeat('a',64)));
$$;
CREATE OR REPLACE FUNCTION pg_temp.f150_h(p_kind text,p_char_from int,p_text text) RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object('element_id','header:'||p_char_from,'kind',p_kind,'page_from',10,'page_to',10,
    'char_from',p_char_from,'char_to',p_char_from+char_length(p_text),'verbatim_text',p_text,
    'verbatim_sha256',encode(extensions.digest(p_text,'sha256'),'hex'));
$$;
