-- Backup af red_opret_person FØR cycle-08 GDPR-hærdning (2026-06-30).
-- Gammel signatur: (text, text, boolean, boolean, text, text, text) — tillader p_privat=false.
-- Efter hærdning: p_privat fjernet — privat ALTID true ved opret; skiftes kun via red_set_privat.

CREATE OR REPLACE FUNCTION public.red_opret_person(p_navn text, p_koen text DEFAULT NULL::text, p_levende boolean DEFAULT false, p_privat boolean DEFAULT true, p_foedt_raw text DEFAULT NULL::text, p_doed_raw text DEFAULT NULL::text, p_titel_raw text DEFAULT NULL::text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_id bigint;
BEGIN
  IF current_rolle() <> 'redaktion' THEN RAISE EXCEPTION 'Kun redaktion'; END IF;
  IF nullif(btrim(p_navn),'') IS NULL THEN RAISE EXCEPTION 'Navn er påkrævet'; END IF;
  IF p_koen IS NOT NULL AND p_koen NOT IN ('mand','kvinde','ukendt')
    THEN RAISE EXCEPTION 'Ugyldigt køn %', p_koen; END IF;
  v_id := (SELECT coalesce(max(id),0)+1 FROM person);
  INSERT INTO person(id, levende, privat, koen) VALUES (v_id, p_levende, p_privat, p_koen);
  PERFORM red_upsert_fakta('person', v_id, 'navn', p_navn);
  IF nullif(btrim(p_foedt_raw),'') IS NOT NULL THEN
    PERFORM red_upsert_fakta('person', v_id, 'fødsel', p_foedt_raw, p_date_raw => p_foedt_raw);
  END IF;
  IF nullif(btrim(p_doed_raw),'') IS NOT NULL THEN
    PERFORM red_upsert_fakta('person', v_id, 'død', p_doed_raw, p_date_raw => p_doed_raw);
  END IF;
  IF nullif(btrim(p_titel_raw),'') IS NOT NULL THEN
    PERFORM red_upsert_fakta('person', v_id, 'titel', p_titel_raw);
  END IF;
  RETURN v_id;
END $function$;
