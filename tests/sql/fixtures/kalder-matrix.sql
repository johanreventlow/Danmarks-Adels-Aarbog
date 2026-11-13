-- Redaktøren ser levende (decisions 2026-11-13): fire kaldere til de offentlige læse-RPC'er.
--   gaest       = anon uden uid
--   uden_profil = authenticated med en uid uden profilrække (current_rolle() giver 'medlem')
--   medlem      = authenticated med profilen 'medlem'
--   redaktion   = authenticated med profilen 'redaktion'
-- current_rolle() læser kun uid'en (auth.uid()), ikke databaserollen. Derfor sætter hver kalder BÅDE rolle og uid,
-- og uid'en sættes tilbage bagefter, så testens videre redaktionsskrivninger kører som før. Indlæses med \ir; kald
-- som ejer, før SET LOCAL ROLE.
CREATE OR REPLACE FUNCTION pg_temp.km_kaldere() RETURNS void LANGUAGE sql AS $$
  INSERT INTO auth.users(id,email) VALUES
    ('11000000-0000-0000-0000-00000000ca01','km-uden-profil@km.invalid'),
    ('11000000-0000-0000-0000-00000000ca02','km-medlem@km.invalid'),
    ('11000000-0000-0000-0000-00000000ca03','km-redaktion@km.invalid')
  ON CONFLICT DO NOTHING;
  INSERT INTO profiles(id,rolle,email) VALUES
    ('11000000-0000-0000-0000-00000000ca02','medlem','km-medlem@km.invalid'),
    ('11000000-0000-0000-0000-00000000ca03','redaktion','km-redaktion@km.invalid')
  ON CONFLICT DO NOTHING;
$$;

-- Antal rækker fra p_sql kørt som p_kalder.
CREATE OR REPLACE FUNCTION pg_temp.km_antal(p_kalder text,p_sql text) RETURNS integer LANGUAGE plpgsql AS $$
DECLARE v_for text:=coalesce(current_setting('request.jwt.claim.sub',true),''); v_uid text; n integer;
BEGIN
  v_uid:=CASE p_kalder WHEN 'gaest' THEN ''
                       WHEN 'uden_profil' THEN '11000000-0000-0000-0000-00000000ca01'
                       WHEN 'medlem' THEN '11000000-0000-0000-0000-00000000ca02'
                       WHEN 'redaktion' THEN '11000000-0000-0000-0000-00000000ca03' END;
  IF v_uid IS NULL THEN RAISE EXCEPTION 'KALDER_MATRIX: ukendt kalder %',p_kalder; END IF;
  PERFORM set_config('request.jwt.claim.sub',v_uid,true);
  EXECUTE format('SET LOCAL ROLE %I',CASE WHEN p_kalder='gaest' THEN 'anon' ELSE 'authenticated' END);
  EXECUTE 'SELECT count(*)::int FROM ('||p_sql||') q' INTO n;
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub',v_for,true);
  RETURN n;
END $$;

-- Forventet antal for alle fire kaldere i én kontrol: p_ikke_red for gaest/uden_profil/medlem, p_red for redaktion.
CREATE OR REPLACE FUNCTION pg_temp.km_forvent(p_navn text,p_sql text,p_ikke_red integer,p_red integer)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE k text; n integer; v_forventet integer;
BEGIN
  FOREACH k IN ARRAY ARRAY['gaest','uden_profil','medlem','redaktion'] LOOP
    n:=pg_temp.km_antal(k,p_sql);
    v_forventet:=CASE WHEN k='redaktion' THEN p_red ELSE p_ikke_red END;
    IF n<>v_forventet THEN
      RAISE EXCEPTION 'KALDER_MATRIX_FAILED: % som %: % rækker, forventede %',p_navn,k,n,v_forventet;
    END IF;
  END LOOP;
END $$;
