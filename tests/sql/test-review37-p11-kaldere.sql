-- Review 37 P11 (#397): kaldermatrix for de to slette-RPC'er med rigtige klientroller (tests/sql/fixtures/kalder-matrix.sql).
-- Gæst, bruger uden profil og medlem får samme afvisning for en offentlig og en ikke-offentlig person (intet orakel:
-- afvisningen siger intet om, hvem personen er). Redaktionen får forhåndsvisningens vej (kan_fortrydes/aarsag), afvises
-- med SLET_KRAEVER_SLET_HELT for den levende og kan slette den offentlige. Listen over slettede personer
-- (red_slettede_personer) afviser alle andre end redaktionen, som ser sletningen. Syntetiske negative id'er; alt rulles tilbage.
-- Forvent: NOTICE "OK: review37 p11 kaldere". Køres af tests/sql/test-review37-p11-upgrade.sh (rød på basen, grøn efter).
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/kalder-matrix.sql
SELECT pg_temp.km_kaldere();

-- Fejlteksten fra p_sql kørt som p_kalder (NULL = ingen fejl). Rollen og uid'en rulles tilbage med undertransaktionen.
CREATE FUNCTION pg_temp.p11_fejl(p_kalder text,p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v_for text:=coalesce(current_setting('request.jwt.claim.sub',true),''); v_msg text;
BEGIN
  BEGIN
    PERFORM pg_temp.km_antal(p_kalder,p_sql);
  EXCEPTION WHEN OTHERS THEN v_msg:=SQLERRM;
  END;
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub',v_for,true);
  PERFORM set_config('app.change_set_id','',true);
  RETURN v_msg;
END $$;

INSERT INTO public.person(id,levende,privat,staged) VALUES
  (-937951,false,false,false),  -- offentlig
  (-937952,true ,false,false),  -- levende
  (-937953,false,true ,false);  -- afdød, privat
SELECT set_config('app.change_set_id','',false);

DO $t$
DECLARE k text; v_off text; v_lev text; v_pv_off text; v_pv_lev text; v_pv jsonb; v_msg text; v_liste text;
BEGIN
  FOREACH k IN ARRAY ARRAY['gaest','uden_profil','medlem'] LOOP
    v_off:=pg_temp.p11_fejl(k,'SELECT public.red_slet_person(-937951)');
    v_lev:=pg_temp.p11_fejl(k,'SELECT public.red_slet_person(-937952)');
    v_pv_off:=pg_temp.p11_fejl(k,'SELECT public.red_slet_person_preview(-937951)');
    v_pv_lev:=pg_temp.p11_fejl(k,'SELECT public.red_slet_person_preview(-937952)');
    IF v_off IS NULL OR v_lev IS NULL OR v_pv_off IS NULL OR v_pv_lev IS NULL THEN
      RAISE EXCEPTION 'KALDER_MATRIX_FAILED: p11 % kunne kalde en slette-RPC (slet: % / %, preview: % / %)',k,v_off,v_lev,v_pv_off,v_pv_lev;
    END IF;
    IF v_off IS DISTINCT FROM v_lev OR v_pv_off IS DISTINCT FROM v_pv_lev
       OR v_lev LIKE '%SLET_KRAEVER_SLET_HELT%' OR v_pv_lev LIKE '%SLET_KRAEVER_SLET_HELT%' THEN
      RAISE EXCEPTION 'KALDER_MATRIX_FAILED: p11 % er et orakel: offentlig «%» / levende «%» (preview «%» / «%»)',
        k,v_off,v_lev,v_pv_off,v_pv_lev;
    END IF;
    -- Listen over slettede personer (navne og id'er på slettede) er kun for redaktionen.
    v_liste:=pg_temp.p11_fejl(k,'SELECT * FROM public.red_slettede_personer()');
    IF v_liste IS NULL THEN
      RAISE EXCEPTION 'KALDER_MATRIX_FAILED: p11 % kunne læse listen over slettede personer',k;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.person WHERE id IN (-937951,-937952) HAVING count(*)=2) THEN
      RAISE EXCEPTION 'KALDER_MATRIX_FAILED: p11 % slettede en person',k;
    END IF;
  END LOOP;

  -- Redaktionen: forhåndsvisningen viser vejen; den levende og den private afvises; den offentlige slettes.
  PERFORM set_config('request.jwt.claim.sub','11000000-0000-0000-0000-00000000ca03',true);
  SET LOCAL ROLE authenticated;
  v_pv:=public.red_slet_person_preview(-937952);
  IF v_pv->'kan_fortrydes' IS DISTINCT FROM 'false'::jsonb OR v_pv->>'aarsag' IS DISTINCT FROM 'levende' THEN
    RESET ROLE; RAISE EXCEPTION 'KALDER_MATRIX_FAILED: p11 redaktion: forhåndsvisningen for den levende er %',v_pv;
  END IF;
  v_pv:=public.red_slet_person_preview(-937951);
  IF v_pv->'kan_fortrydes' IS DISTINCT FROM 'true'::jsonb OR v_pv->'aarsag' IS DISTINCT FROM 'null'::jsonb THEN
    RESET ROLE; RAISE EXCEPTION 'KALDER_MATRIX_FAILED: p11 redaktion: forhåndsvisningen for den offentlige er %',v_pv;
  END IF;
  RESET ROLE;
  v_msg:=pg_temp.p11_fejl('redaktion','SELECT public.red_slet_person(-937952)');
  IF v_msg IS NULL OR v_msg NOT LIKE 'SLET_KRAEVER_SLET_HELT: levende %' THEN
    RAISE EXCEPTION 'KALDER_MATRIX_FAILED: p11 redaktion slettede den levende simpelt (fejl: %)',coalesce(v_msg,'ingen');
  END IF;
  v_msg:=pg_temp.p11_fejl('redaktion','SELECT public.red_slet_person(-937953)');
  IF v_msg IS NULL OR v_msg NOT LIKE 'SLET_KRAEVER_SLET_HELT: privat %' THEN
    RAISE EXCEPTION 'KALDER_MATRIX_FAILED: p11 redaktion slettede den private simpelt (fejl: %)',coalesce(v_msg,'ingen');
  END IF;
  v_msg:=pg_temp.p11_fejl('redaktion','SELECT public.red_slet_person(-937951)');
  IF v_msg IS NOT NULL OR EXISTS (SELECT 1 FROM public.person WHERE id=-937951)
     OR NOT EXISTS (SELECT 1 FROM public.person WHERE id IN (-937952,-937953) HAVING count(*)=2) THEN
    RAISE EXCEPTION 'KALDER_MATRIX_FAILED: p11 redaktion: den offentlige blev ikke slettet, eller en anden blev (fejl: %)',
      coalesce(v_msg,'ingen');
  END IF;
  v_msg:=pg_temp.p11_fejl('redaktion','SELECT * FROM public.red_slettede_personer() WHERE person_id=-937951');
  IF v_msg IS NOT NULL OR pg_temp.km_antal('redaktion','SELECT * FROM public.red_slettede_personer() WHERE person_id=-937951')<>1 THEN
    RAISE EXCEPTION 'KALDER_MATRIX_FAILED: p11 redaktion: den slettede står ikke på listen (fejl: %)',coalesce(v_msg,'ingen');
  END IF;
  RAISE NOTICE 'OK: review37 p11 kaldere';
END $t$;
ROLLBACK;
