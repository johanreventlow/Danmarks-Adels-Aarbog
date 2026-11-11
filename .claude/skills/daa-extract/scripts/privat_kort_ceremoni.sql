-- Trin 6d-3 (plan Task 7, spor O): skjul importlevn. I ÉN transaktion: red_set_privat(<skjul_person>, true) altid
-- (projektejerens valg, spec §5.4 b) og red_set_privat(<O-kortets person>, true) for hvert O-kort med svaret `P`
-- (`B` = bliv stående, intet skrives). Kildeparametriseret gennem manifestet; person- og familie-id'er kommer fra
-- manifestet og -v-parametrene, ingen udgaver eller id'er i logikken. Kræver D's kvittering (samme_som_kort_ceremoni.sql)
-- for kilden: rækkefølgen er D, O, så R.
--
-- Filer: samme manifest og svarfil som D (formater: se samme_som_kort_ceremoni.sql); D-kortene efterprøves ikke her
-- (D har skrevet), men hele svarfilen valideres igen (ét svar pr. kort, i svar_tilladt).
-- Førtilstand (under rækkelås på personerne, før første mutation):
--   skjul_person  privat=false; partner i hver af -v familier.
--   familier      medlemskabet uændret: md5 over family_member-rækkerne for familierne skal være -v familie_md5, hvor
--                 md5 = SELECT md5(coalesce(string_agg(concat_ws('|',fm.family_id,fm.person_id,fm.rolle,
--                         coalesce(fm.ordinal::text,'-'),coalesce(fm.konfidens,'-')),E'\n'
--                         ORDER BY fm.family_id,fm.person_id,fm.rolle COLLATE "C"),''))
--                       FROM public.family_member fm WHERE fm.family_id=ANY('{<familier>}'::bigint[]);
--                 (runneren beregner det samme udtryk ved kortenes udstedelse; ved afvigelse nævner fejlen den beregnede md5)
--   O-kort        person findes, privat = forventet_foer.privat (false), og tekst_sha256 = sha256 af kanonisk JSON
--                 {"narrativ": tekst|null} for personens første narrativ (subjekt_type='person', ORDER BY id, uden kildefilter).
-- Efterbetingelser: de skjulte har privat=true, og family_offentlig(f) er falsk for hver af familierne.
-- Kvittering: en change_set uden hændelser, operation 'privat_kort_ceremoni', kilden som subjekt, summary
-- `T6D3_O_OK privat=<n>` (n = antal personer sat privat), skrevet sidst; ceremonien udskriver samme linje. Hver
-- red_set_privat har sin egen change_set (app.change_set_id nulstilles mellem kald).
-- Fejlkoder: T6D3_PRE_* (intet skrevet; som D: ARGS/ROLE/GUC/TIMEOUT/SHA/FASE/SVAR/MANIFEST), T6D3_POST_* (alt rulles
-- tilbage). PRE_FASE: O's kvittering findes allerede, eller D's mangler.
-- Brug: psql -X -At -v ON_ERROR_STOP=1 -v actor=<uuid> -v manifest_path=<fil> -v manifest_sha=<sha256>
--   -v svar_path=<fil> -v svar_sha=<sha256> -v skjul_person=<person-id> -v familier=<id>,<id> -v familie_md5=<md5>
--   -f privat_kort_ceremoni.sql
\set QUIET on
\set ON_ERROR_STOP on
\encoding UTF8
\set m `cat :'manifest_path'`
\set sv `cat :'svar_path'`
BEGIN;
SET LOCAL statement_timeout = '15min';
DO $timeout$ BEGIN IF current_setting('statement_timeout')<>'15min' THEN RAISE EXCEPTION 'T6D3_PRE_TIMEOUT'; END IF; END $timeout$;
SELECT set_config('request.jwt.claim.sub', :'actor', true), set_config('t6d3.manifest_sha', :'manifest_sha', true),
       set_config('t6d3.svar_sha', :'svar_sha', true), set_config('t6d3.skjul_person', :'skjul_person', true),
       set_config('t6d3.familier', :'familier', true), set_config('t6d3.familie_md5', :'familie_md5', true) \g /dev/null
CREATE TEMP TABLE t6d3_input ON COMMIT DROP AS SELECT :'m'::text AS m_text, :'sv'::text AS sv_text;
CREATE TEMP TABLE t6d3_kort (ord integer PRIMARY KEY, kort text NOT NULL UNIQUE, handling text NOT NULL, k jsonb NOT NULL,
  svar text, objekt bigint) ON COMMIT DROP;

CREATE FUNCTION pg_temp.t6d3_sha(p_text text) RETURNS text LANGUAGE sql IMMUTABLE AS
  $f$ SELECT encode(sha256(convert_to(p_text,'UTF8')),'hex') $f$;

-- Svarfil og manifest: fælles validering for D og O (O-ceremonien har en ordret kopi; test_maal_trin6d3.py låser den).
-- Returnerer kilden; fylder t6d3_kort med alle kort og deres svar.
CREATE FUNCTION pg_temp.t6d3_filer(p_kode text) RETURNS bigint LANGUAGE plpgsql AS $f$
DECLARE v_msha text:=current_setting('t6d3.manifest_sha'); v_ssha text:=current_setting('t6d3.svar_sha');
  i record; m jsonb; sv jsonb; v_k jsonb; v_ord integer:=0; v_src bigint; v_svar text; r record;
BEGIN
  SELECT * INTO i FROM t6d3_input;
  IF v_msha NOT IN (pg_temp.t6d3_sha(i.m_text),pg_temp.t6d3_sha(i.m_text||E'\n'))
     OR v_ssha NOT IN (pg_temp.t6d3_sha(i.sv_text),pg_temp.t6d3_sha(i.sv_text||E'\n')) THEN
    RAISE EXCEPTION '%_PRE_SHA filer',p_kode;
  END IF;
  BEGIN m:=i.m_text::jsonb; EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION '%_PRE_MANIFEST skema',p_kode; END;
  BEGIN sv:=i.sv_text::jsonb; EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION '%_PRE_SVAR skema',p_kode; END;
  IF jsonb_typeof(sv)<>'object' OR sv->>'contract' IS DISTINCT FROM 'trin6d3-kortsvar-v1' OR jsonb_typeof(sv->'svar')<>'object' THEN
    RAISE EXCEPTION '%_PRE_SVAR kontrakt',p_kode;
  END IF;
  IF sv->>'manifest_sha256' IS DISTINCT FROM v_msha THEN RAISE EXCEPTION '%_PRE_SHA manifest_sha256',p_kode; END IF;
  IF jsonb_typeof(m)<>'object' OR m->>'contract' IS DISTINCT FROM 'trin6d3-kortmanifest-v1'
     OR coalesce(m->>'source_id','') !~ '^-?[0-9]+$' OR jsonb_typeof(m->'kort')<>'array' OR jsonb_array_length(m->'kort')=0 THEN
    RAISE EXCEPTION '%_PRE_MANIFEST kontrakt',p_kode;
  END IF;
  v_src:=(m->>'source_id')::bigint;
  IF NOT EXISTS (SELECT 1 FROM public.source WHERE id=v_src) THEN RAISE EXCEPTION '%_PRE_MANIFEST kilde',p_kode; END IF;
  FOR v_k IN SELECT x FROM jsonb_array_elements(m->'kort') x LOOP
    v_ord:=v_ord+1;
    IF jsonb_typeof(v_k)<>'object' OR coalesce(v_k->>'kort','')='' OR coalesce(v_k->>'handling','') NOT IN ('samme_som','privat')
       OR jsonb_typeof(v_k->'svar_tilladt')<>'array' OR jsonb_typeof(v_k->'forventet_foer')<>'object'
       OR coalesce(v_k->>'tekst_sha256','') !~ '^[0-9a-f]{64}$' THEN
      RAISE EXCEPTION '%_PRE_MANIFEST skema (kort nr. %)',p_kode,v_ord;
    END IF;
    IF EXISTS (SELECT 1 FROM t6d3_kort WHERE kort=v_k->>'kort') THEN RAISE EXCEPTION '%_PRE_MANIFEST dublet %',p_kode,v_k->>'kort'; END IF;
    INSERT INTO t6d3_kort(ord,kort,handling,k) VALUES (v_ord,v_k->>'kort',v_k->>'handling',v_k);
  END LOOP;
  -- Svarene: ét pr. manifestkort, intet ekstra, hvert i kortets svar_tilladt.
  IF EXISTS (SELECT 1 FROM jsonb_object_keys(sv->'svar') x WHERE x NOT IN (SELECT kort FROM t6d3_kort)) THEN
    RAISE EXCEPTION '%_PRE_SVAR ukendt kort',p_kode;
  END IF;
  FOR r IN SELECT * FROM t6d3_kort ORDER BY ord LOOP
    IF jsonb_typeof(sv->'svar'->r.kort) IS DISTINCT FROM 'string' THEN RAISE EXCEPTION '%_PRE_SVAR kort % uden svar',p_kode,r.kort; END IF;
    v_svar:=sv->'svar'->>r.kort;
    IF NOT (r.k->'svar_tilladt') @> to_jsonb(ARRAY[v_svar]) THEN RAISE EXCEPTION '%_PRE_SVAR kort % svar uden for svar_tilladt',p_kode,r.kort; END IF;
    UPDATE t6d3_kort SET svar=v_svar WHERE ord=r.ord;
  END LOOP;
  RETURN v_src;
END $f$;

-- Familiernes medlemskabs-md5 (udtrykket i hovedkommentaren).
CREATE FUNCTION pg_temp.t6d3_familie_md5(p_fids bigint[]) RETURNS text LANGUAGE sql STABLE AS $f$
  SELECT md5(coalesce(string_agg(concat_ws('|',fm.family_id,fm.person_id,fm.rolle,
           coalesce(fm.ordinal::text,'-'),coalesce(fm.konfidens,'-')),E'\n'
           ORDER BY fm.family_id,fm.person_id,fm.rolle COLLATE "C"),''))
    FROM public.family_member fm WHERE fm.family_id=ANY(p_fids);
$f$;

DO $pre$
DECLARE v_src bigint; v_skjul bigint; v_fids bigint[]; r record; v_fejl text[]:='{}'; v_why text[]; v_md5 text; v_privat boolean;
  v_sha text;
BEGIN
  IF current_setting('t6d3.manifest_sha') !~ '^[0-9a-f]{64}$' OR current_setting('t6d3.svar_sha') !~ '^[0-9a-f]{64}$'
     OR current_setting('request.jwt.claim.sub') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     OR current_setting('t6d3.skjul_person') !~ '^-?[0-9]+$' OR current_setting('t6d3.familier') !~ '^-?[0-9]+(,-?[0-9]+)*$'
     OR current_setting('t6d3.familie_md5') !~ '^[0-9a-f]{32}$' THEN
    RAISE EXCEPTION 'T6D3_PRE_ARGS';
  END IF;
  v_skjul:=current_setting('t6d3.skjul_person')::bigint;
  v_fids:=string_to_array(current_setting('t6d3.familier'),',')::bigint[];
  IF public.current_rolle() IS DISTINCT FROM 'redaktion' THEN RAISE EXCEPTION 'T6D3_PRE_ROLE'; END IF;
  IF btrim(coalesce(current_setting('app.change_set_id',true),''))<>'' THEN RAISE EXCEPTION 'T6D3_PRE_GUC'; END IF;
  v_src:=pg_temp.t6d3_filer('T6D3');
  PERFORM set_config('t6d3.src',v_src::text,true);
  IF EXISTS (SELECT 1 FROM public.change_set WHERE operation='privat_kort_ceremoni' AND summary LIKE 'T6D3\_O\_OK %'
              AND subjekt_type='source' AND subjekt_id=v_src)
     OR NOT EXISTS (SELECT 1 FROM public.change_set WHERE operation='samme_som_kort_ceremoni' AND summary LIKE 'T6D3\_D\_OK %'
                     AND subjekt_type='source' AND subjekt_id=v_src) THEN
    RAISE EXCEPTION 'T6D3_PRE_FASE';
  END IF;
  FOR r IN SELECT * FROM t6d3_kort WHERE handling='privat' ORDER BY ord LOOP
    IF coalesce(r.k->>'person_id','') !~ '^-?[0-9]+$' OR jsonb_typeof(r.k#>'{forventet_foer,privat}')<>'boolean'
       OR EXISTS (SELECT 1 FROM jsonb_array_elements_text(r.k->'svar_tilladt') t WHERE t NOT IN ('B','P')) THEN
      RAISE EXCEPTION 'T6D3_PRE_MANIFEST skema (kort %)',r.kort;
    END IF;
    IF r.svar='P' THEN UPDATE t6d3_kort SET objekt=(r.k->>'person_id')::bigint WHERE ord=r.ord; END IF;
  END LOOP;
  -- Codex T7 fund 1: familiemedlemskabet fryses til COMMIT (SHARE blokerer andres INSERT/UPDATE/DELETE, også
  -- red_slet_familie_link, der ikke tager person- eller familielåse); ceremonien varer sekunder under meldt frys.
  LOCK TABLE public.family_member IN SHARE MODE;
  -- Lås personerne (den skjulte og O-kortenes) og familierne; efterprøv kvitteringen igen under låsen.
  PERFORM 1 FROM public.person WHERE id=v_skjul
       OR id IN (SELECT (k->>'person_id')::bigint FROM t6d3_kort WHERE handling='privat') ORDER BY id FOR UPDATE;
  PERFORM 1 FROM public.family WHERE id=ANY(v_fids) ORDER BY id FOR UPDATE;
  IF EXISTS (SELECT 1 FROM public.change_set WHERE operation='privat_kort_ceremoni' AND summary LIKE 'T6D3\_O\_OK %'
              AND subjekt_type='source' AND subjekt_id=v_src) THEN
    RAISE EXCEPTION 'T6D3_PRE_FASE';
  END IF;
  -- Den skjulte person og familierne.
  SELECT privat INTO v_privat FROM public.person WHERE id=v_skjul;
  IF NOT FOUND OR coalesce(v_privat,false) THEN v_fejl:=v_fejl||'skjul_person'::text; END IF;
  IF EXISTS (SELECT 1 FROM unnest(v_fids) f WHERE NOT EXISTS (SELECT 1 FROM public.family_member fm
               WHERE fm.family_id=f AND fm.person_id=v_skjul AND fm.rolle='partner')) THEN
    v_fejl:=v_fejl||'familier (skjul_person er ikke partner)'::text;
  END IF;
  -- Codex T7 fund 2: familielisten skal være præcis alle familier (enhver rolle) for de personer, der skjules —
  -- den obligatoriske og O-kortenes P-personer; en ekstra eller manglende familie stopper før første mutation.
  IF EXISTS (SELECT f FROM unnest(v_fids) f
             EXCEPT SELECT fm.family_id FROM public.family_member fm
              WHERE fm.person_id=v_skjul OR fm.person_id IN (SELECT objekt FROM t6d3_kort WHERE handling='privat' AND objekt IS NOT NULL))
     OR EXISTS (SELECT fm.family_id FROM public.family_member fm
              WHERE fm.person_id=v_skjul OR fm.person_id IN (SELECT objekt FROM t6d3_kort WHERE handling='privat' AND objekt IS NOT NULL)
             EXCEPT SELECT f FROM unnest(v_fids) f) THEN
    v_fejl:=v_fejl||'familier (mængden svarer ikke til de skjultes familier)'::text;
  END IF;
  v_md5:=pg_temp.t6d3_familie_md5(v_fids);
  IF v_md5<>current_setting('t6d3.familie_md5') THEN v_fejl:=v_fejl||format('familier (beregnet %s)',v_md5); END IF;
  -- O-kortene.
  FOR r IN SELECT * FROM t6d3_kort WHERE handling='privat' ORDER BY ord LOOP
    v_why:='{}';
    SELECT privat INTO v_privat FROM public.person WHERE id=(r.k->>'person_id')::bigint;
    IF NOT FOUND OR coalesce(v_privat,false) IS DISTINCT FROM (r.k#>>'{forventet_foer,privat}')::boolean OR coalesce(v_privat,false) THEN
      v_why:=v_why||'privat'::text;
    END IF;
    v_sha:=private.reimport_canonical_json_sha256(jsonb_build_object(
      'narrativ',(SELECT to_jsonb(n.tekst) FROM public.narrative n
                   WHERE n.subjekt_type='person' AND n.subjekt_id=(r.k->>'person_id')::bigint ORDER BY n.id LIMIT 1)));
    IF v_sha IS DISTINCT FROM r.k->>'tekst_sha256' THEN v_why:=v_why||'tekst'::text; END IF;
    IF cardinality(v_why)>0 THEN v_fejl:=v_fejl||format('%s (%s)',r.kort,array_to_string(v_why,',')); END IF;
  END LOOP;
  IF cardinality(v_fejl)>0 THEN RAISE EXCEPTION 'T6D3_PRE_MANIFEST kort %',array_to_string(v_fejl,', '); END IF;
END $pre$;

DO $write$
DECLARE v_src bigint:=current_setting('t6d3.src')::bigint; v_skjul bigint:=current_setting('t6d3.skjul_person')::bigint;
  v_fids bigint[]:=string_to_array(current_setting('t6d3.familier'),',')::bigint[]; v_ids bigint[]; v_id bigint; v_rcs bigint;
BEGIN
  v_ids:=ARRAY(SELECT DISTINCT x FROM unnest(array_prepend(v_skjul,ARRAY(SELECT objekt FROM t6d3_kort WHERE handling='privat'
                                                                     AND objekt IS NOT NULL))) x ORDER BY x);
  FOREACH v_id IN ARRAY v_ids LOOP
    PERFORM set_config('app.change_set_id','',true);
    PERFORM public.red_set_privat(v_id,true);
    PERFORM set_config('app.change_set_id','',true);
  END LOOP;
  IF EXISTS (SELECT 1 FROM unnest(v_ids) x WHERE NOT EXISTS (SELECT 1 FROM public.person p WHERE p.id=x AND p.privat)) THEN
    RAISE EXCEPTION 'T6D3_POST_PRIVAT';
  END IF;
  IF EXISTS (SELECT 1 FROM unnest(v_fids) f WHERE public.family_offentlig(f)) THEN RAISE EXCEPTION 'T6D3_POST_FAMILIE'; END IF;
  v_rcs:=public.begin_change_set('privat_kort_ceremoni',format('T6D3_O_OK privat=%s',cardinality(v_ids)),'source',v_src);
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('t6d3.kvittering',v_rcs::text,true);
END $write$;
SELECT set_config('t6d3.kvittering_ud',current_setting('t6d3.kvittering'),false) \g /dev/null
COMMIT;
SELECT summary FROM public.change_set WHERE id=current_setting('t6d3.kvittering_ud')::bigint;
