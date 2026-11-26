-- Review 37 R37S8-1 (#397): kaldermatrix for redaktionens to medie-RPC'er med rigtige klientroller
-- (tests/sql/fixtures/kalder-matrix.sql). Gæsten (anon) har ingen EXECUTE (42501, »permission denied«); bruger uden
-- profil og medlem (authenticated) afvises med »Kun redaktion« — også ved ugyldigt input, så afvisningen intet afslører.
-- Redaktionen får original_filnavn/sha256 flettet på id og dublettjekkets ene række. Blok B (review37-c5b): direkte på
-- tabellen er de to kolonner (også som filter) lukket for ALLE fire kaldere, redaktionen med. Syntetiske negative id'er;
-- alt rulles tilbage. Forvent: NOTICE "OK: review37 c5 kaldere". Køres i CI mod frisk schema (»Evidens-hardening på frisk
-- schema-sti«) og af test-review37-c5-upgrade.sh efter blok B.
\set ON_ERROR_STOP on
BEGIN;
\ir fixtures/kalder-matrix.sql
SELECT pg_temp.km_kaldere();

-- Fejlteksten og SQLSTATE fra p_sql kørt som p_kalder (NULL = ingen fejl). Rollen og uid'en sættes tilbage.
CREATE FUNCTION pg_temp.c5_fejl(p_kalder text,p_sql text) RETURNS text LANGUAGE plpgsql AS $$
DECLARE v_for text:=coalesce(current_setting('request.jwt.claim.sub',true),''); v_msg text;
BEGIN
  BEGIN
    PERFORM pg_temp.km_antal(p_kalder,p_sql);
  EXCEPTION WHEN OTHERS THEN v_msg:=SQLSTATE||' '||SQLERRM;
  END;
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub',v_for,true);
  RETURN v_msg;
END $$;

SELECT set_config('app.change_set_id','',false);
INSERT INTO public.media(id,slags,titel,upload_status,storage_path,original_filnavn,sha256) VALUES
  (-937801,'foto','c5 kaldere','klar','c5/-937801.jpg','Privat navn.jpg',repeat('5c',32));

DO $t$
DECLARE k text; v_msg text; v_n int; q text;
BEGIN
  FOREACH k IN ARRAY ARRAY['gaest','uden_profil','medlem'] LOOP
    FOREACH q IN ARRAY ARRAY[
        'SELECT * FROM public.red_media_interne_felter(ARRAY[-937801]::bigint[])',
        'SELECT * FROM public.red_media_interne_felter(NULL)',
        'SELECT * FROM public.red_media_efter_sha(repeat(''5c'',32))',
        'SELECT * FROM public.red_media_efter_sha(''ugyldig'')'] LOOP
      v_msg:=pg_temp.c5_fejl(k,q);
      IF (k='gaest' AND v_msg NOT LIKE '42501 permission denied for function red_media_%')
         OR (k<>'gaest' AND v_msg IS DISTINCT FROM 'P0001 Kun redaktion') THEN
        RAISE EXCEPTION 'KALDER_MATRIX_FAILED: c5 % fik «%» for %',k,coalesce(v_msg,'(succes)'),q;
      END IF;
    END LOOP;
  END LOOP;

  v_n:=pg_temp.km_antal('redaktion',
    'SELECT 1 FROM public.red_media_interne_felter(ARRAY[-937801,-937899]::bigint[])
      WHERE id=-937801 AND original_filnavn=''Privat navn.jpg'' AND sha256=repeat(''5c'',32)');
  IF v_n<>1 THEN RAISE EXCEPTION 'KALDER_MATRIX_FAILED: c5 redaktion fik % rækker fra red_media_interne_felter',v_n; END IF;
  v_n:=pg_temp.km_antal('redaktion',
    'SELECT 1 FROM public.red_media_efter_sha(repeat(''5c'',32))
      WHERE id=-937801 AND titel=''c5 kaldere'' AND upload_status=''klar'' AND storage_path=''c5/-937801.jpg''');
  IF v_n<>1 THEN RAISE EXCEPTION 'KALDER_MATRIX_FAILED: c5 redaktion fik % rækker fra red_media_efter_sha',v_n; END IF;
  v_msg:=pg_temp.c5_fejl('redaktion','SELECT * FROM public.red_media_efter_sha(''ugyldig'')');
  IF v_msg NOT LIKE '22023 MEDIA_SHA_UGYLDIG%' THEN
    RAISE EXCEPTION 'KALDER_MATRIX_FAILED: c5 redaktion: ugyldig sha gav «%»',coalesce(v_msg,'(succes)');
  END IF;
  -- Blok B: ingen kalder læser de interne kolonner direkte, mens læserens kolonner virker for alle.
  FOREACH k IN ARRAY ARRAY['gaest','uden_profil','medlem','redaktion'] LOOP
    FOREACH q IN ARRAY ARRAY[
        'SELECT original_filnavn FROM public.media',
        'SELECT sha256 FROM public.media',
        'SELECT id FROM public.media WHERE sha256=repeat(''5c'',32)'] LOOP
      v_msg:=pg_temp.c5_fejl(k,q);
      IF v_msg IS NULL OR v_msg NOT LIKE '42501 permission denied for table media' THEN
        RAISE EXCEPTION 'KALDER_MATRIX_FAILED: c5 % læste direkte (%): %',k,coalesce(v_msg,'ingen fejl'),q;
      END IF;
    END LOOP;
    v_msg:=pg_temp.c5_fejl(k,'SELECT id,titel,storage_path,upload_status FROM public.media');
    IF v_msg IS NOT NULL THEN RAISE EXCEPTION 'KALDER_MATRIX_FAILED: c5 % kan ikke læse læserens kolonner: %',k,v_msg; END IF;
  END LOOP;
  RAISE NOTICE 'OK: review37 c5 kaldere';
END $t$;
ROLLBACK;
