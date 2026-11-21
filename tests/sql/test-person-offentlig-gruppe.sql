-- #415: synlighed pr. samme_som-gruppe. En række er kun offentlig, hvis ingen anden række for samme menneske er
-- levende (også NULL) eller privat; staged smitter ikke. Kører på frisk schema + db-rls. Syntetiske negative id'er;
-- alt rulles tilbage. Forvent: NOTICE "OK: person_offentlig pr. samme_som-gruppe".
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/kalder-matrix.sql
SELECT pg_temp.km_kaldere();

-- samme_som oprettes og fjernes gennem redaktørens RPC'er (triggerne og change_set-vejen køres som i appen).
CREATE FUNCTION pg_temp.g_link(p_a bigint,p_b bigint) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v bigint;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','11000000-0000-0000-0000-00000000ca03',true);
  PERFORM set_config('app.change_set_id','',true);
  SET LOCAL ROLE authenticated;
  v:=public.red_samme_som(p_a,p_b);
  RESET ROLE;
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('request.jwt.claim.sub','',true);
  RETURN v;
END $$;
CREATE FUNCTION pg_temp.g_unlink(p_rel bigint) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM set_config('request.jwt.claim.sub','11000000-0000-0000-0000-00000000ca03',true);
  PERFORM set_config('app.change_set_id','',true);
  SET LOCAL ROLE authenticated;
  PERFORM public.red_fjern_samme_som(p_rel);
  RESET ROLE;
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('request.jwt.claim.sub','',true);
END $$;
-- Synlige person-rækker blandt p_ids for hver kalder: gæst/medlem ser p_ikke_red, redaktion ser alle.
CREATE FUNCTION pg_temp.g_ser(p_navn text,p_ids bigint[],p_ikke_red int) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  PERFORM pg_temp.km_forvent(p_navn,format('SELECT 1 FROM public.person WHERE id = ANY (%L::bigint[])',p_ids),
    p_ikke_red,cardinality(p_ids));
END $$;
CREATE FUNCTION pg_temp.g_floruit(p_pid bigint,p_forventet text,p_trin text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE v text;
BEGIN
  SELECT visning_floruit INTO v FROM public.person WHERE id=p_pid;
  IF v IS DISTINCT FROM p_forventet THEN
    RAISE EXCEPTION 'GRUPPE_TEST_FAILED: floruit %: person % forventede %, fik %',p_trin,p_pid,
      coalesce(p_forventet,'NULL'),coalesce(v,'NULL');
  END IF;
END $$;

INSERT INTO public.person(id,levende,privat,staged) VALUES
  (-415001,true ,false,false),  -- levende kanonisk
  (-415002,false,false,false),  --   1939-alias af -415001 (lækagen fra 2026-11-21)
  (-415011,false,false,false),  -- død kanonisk
  (-415012,true ,false,false),  --   levende alias (omvendt retning)
  (-415021,false,false,false),  -- stjerne: kanonisk
  (-415022,false,false,false),  --   alias
  (-415023,true ,false,false),  --   alias, levende → hele stjernen skjult
  (-415031,false,false,false),  -- død kanonisk
  (-415032,false,true ,false),  --   privat alias
  (-415041,false,false,false),  -- død kanonisk
  (-415042,NULL ,false,false),  --   alias med ukendt levende
  (-415051,false,false,false),  -- død kanonisk
  (-415052,false,false,true ),  --   staged alias: smitter IKKE
  (-415061,false,false,false);  -- enlig, ingen samme_som

DO $t$
DECLARE r1 bigint;
BEGIN
  PERFORM pg_temp.g_link(-415002,-415001);
  PERFORM pg_temp.g_link(-415012,-415011);
  PERFORM pg_temp.g_link(-415022,-415021);
  PERFORM pg_temp.g_link(-415023,-415021);
  PERFORM pg_temp.g_link(-415032,-415031);
  PERFORM pg_temp.g_link(-415042,-415041);
  PERFORM pg_temp.g_link(-415052,-415051);

  -- Hjælperen og person_offentlig som ejer.
  IF public.person_offentlig(-415002) OR public.person_offentlig(-415011) OR public.person_offentlig(-415021)
     OR public.person_offentlig(-415022) OR public.person_offentlig(-415031) OR public.person_offentlig(-415041) THEN
    RAISE EXCEPTION 'GRUPPE_TEST_FAILED: et gruppemedlem af en levende/privat/ukendt er offentligt';
  END IF;
  IF NOT public.person_offentlig(-415051) OR public.person_offentlig(-415052) OR NOT public.person_offentlig(-415061) THEN
    RAISE EXCEPTION 'GRUPPE_TEST_FAILED: staged smitter, eller staged/enlig har forkert synlighed';
  END IF;
  IF public.person_gruppe_skjult(-415061) OR public.person_gruppe_skjult(-415051) OR NOT public.person_gruppe_skjult(-415002) THEN
    RAISE EXCEPTION 'GRUPPE_TEST_FAILED: person_gruppe_skjult';
  END IF;
END $t$;

-- Tabel-RLS som de fire kaldere: kun -415051 og -415061 er offentlige; redaktion ser alle 14.
SELECT pg_temp.g_ser('person-rækker',ARRAY[-415001,-415002,-415011,-415012,-415021,-415022,-415023,-415031,-415032,
  -415041,-415042,-415051,-415052,-415061]::bigint[],2);
SELECT pg_temp.g_ser('levende-alias',ARRAY[-415002]::bigint[],0);
SELECT pg_temp.g_ser('omvendt',ARRAY[-415011]::bigint[],0);
SELECT pg_temp.g_ser('stjerne',ARRAY[-415021,-415022]::bigint[],0);
SELECT pg_temp.g_ser('privat',ARRAY[-415031]::bigint[],0);
SELECT pg_temp.g_ser('ukendt levende',ARRAY[-415041]::bigint[],0);
SELECT pg_temp.g_ser('staged smitter ikke',ARRAY[-415051]::bigint[],1);

-- Kaskaden til fakta, relationer og narrativer på aliaset (entitet_offentlig).
INSERT INTO public.fact(id,subjekt_type,subjekt_id,faktatype) VALUES
  (-415101,'person',-415002,'erhverv'),(-415102,'person',-415061,'erhverv');
INSERT INTO public.narrative(id,subjekt_type,subjekt_id,tekst) VALUES
  (-415111,'person',-415002,'alias-prosa'),(-415112,'person',-415061,'enlig-prosa');
SELECT pg_temp.km_forvent('fakta',
  'SELECT 1 FROM public.fact WHERE id IN (-415101,-415102)',1,2);
SELECT pg_temp.km_forvent('narrativer',
  'SELECT 1 FROM public.narrative WHERE id IN (-415111,-415112)',1,2);
-- samme_som-kanten mellem levende og alias er heller ikke synlig for læseren.
SELECT pg_temp.km_forvent('samme_som-kant',
  'SELECT 1 FROM public.relation WHERE rolle=''samme_som'' AND subjekt_id IN (-415002,-415001) AND objekt_id IN (-415002,-415001)',0,1);

-- Cache: visning_floruit for en offentlig partner i en familie med aliaset følger gruppens synlighed, både når den
-- levende kanoniske ændrer flag (person-triggeren) og når samme_som-kanten fjernes eller oprettes (relation-triggeren).
DO $t$
DECLARE r1 bigint;
BEGIN
  INSERT INTO public.family(id) VALUES (-415201);
  INSERT INTO public.family_member(family_id,person_id,rolle) VALUES (-415201,-415061,'partner'),(-415201,-415002,'partner');
  INSERT INTO public.fact(id,subjekt_type,subjekt_id,faktatype) VALUES (-415202,'family',-415201,'vielse');
  INSERT INTO public.assertion(id,target_type,target_id,date_raw,date_min,date_max)
    VALUES (-415203,'fact',-415202,'1850','1850-01-01','1850-12-31');
  INSERT INTO public.conclusion(target_type,target_id,valgt_assertion_id,status) VALUES ('fact',-415202,-415203,'afklaret');
  PERFORM pg_temp.g_floruit(-415061,NULL,'familie skjult af levende kanonisk');
  IF public.family_offentlig(-415201) THEN RAISE EXCEPTION 'GRUPPE_TEST_FAILED: familie med alias af levende er offentlig'; END IF;

  UPDATE public.person SET levende=false WHERE id=-415001;
  PERFORM pg_temp.g_floruit(-415061,'1850','kanonisk død → familie offentlig');
  UPDATE public.person SET levende=true WHERE id=-415001;
  PERFORM pg_temp.g_floruit(-415061,NULL,'kanonisk levende igen');

  SELECT id INTO r1 FROM public.relation WHERE rolle='samme_som' AND subjekt_id IN (-415001,-415002)
     AND objekt_id IN (-415001,-415002);
  PERFORM pg_temp.g_unlink(r1);
  IF NOT public.person_offentlig(-415002) THEN RAISE EXCEPTION 'GRUPPE_TEST_FAILED: alias uden kant er stadig skjult'; END IF;
  PERFORM pg_temp.g_floruit(-415061,'1850','kant fjernet');
  PERFORM pg_temp.g_link(-415002,-415001);
  PERFORM pg_temp.g_floruit(-415061,NULL,'kant genoprettet');
END $t$;

DO $t$ BEGIN RAISE NOTICE 'OK: person_offentlig pr. samme_som-gruppe'; END $t$;
ROLLBACK;
