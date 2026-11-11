-- Trin 6d-3 (plan Task 7, spor D): den dobbelte ægtefælle. I ÉN transaktion anvendes projektejerens svar på D-kortene:
-- `S <n>` → red_samme_som(1939-ægtefællerækken som alias, n), `I` → intet skrives (svaret står kun i kortarket og her).
-- Kildeparametriseret gennem manifestet; nævner hverken udgaver, kilde-id'er eller person-id'er i logikken.
-- Rækkefølge i dataceremonien: D, så O (privat_kort_ceremoni.sql kræver D's kvittering), så R. Kortenes tekst-sha
-- bygger på private.relation_persona_input, som udelader påstande med parter; den er derfor kun gyldig før R's
-- persona-batch (som D's plads i rækkefølgen sikrer).
--
-- Filer (formater fastlagt af det private kortværktøj; læses klientside med \set … `cat`, aldrig \copy):
--   manifest  kanonisk JSON + "\n": {contract:'trin6d3-kortmanifest-v1', source_id, tekst_sha_definition, kort:[…]};
--             D-kort {kort, handling:'samme_som', family_id_1939, hovedperson_id, hovedperson_kanonisk, alias_person_id,
--             mulige_objekter:[kanoniske id'er, sorteret], forventet_foer{alias_samme_som:false, tvilling_aegtefaeller},
--             tekst_sha256, svar_tilladt:['I','S <id>',…]}; O-kort {kort, handling:'privat', person_id,
--             forventet_foer{privat:false}, tekst_sha256, svar_tilladt:['B','P']} (O-kortene efterprøves af O-ceremonien).
--   svar      {contract:'trin6d3-kortsvar-v1', manifest_sha256, svar:{<kort>:<svar>}}; ukendte topnøgler (fx
--             ompraeget_fra) ignoreres. Ét svar pr. manifestkort, intet ekstra, hvert svar ∈ kortets svar_tilladt.
--   psql's backtick fjerner én afsluttende linjeskift; de bundne sha'er accepteres med og uden (som 6d-2a).
--
-- Definitioner (ordret fra kortværktøjet; efterprøves for ALLE D-kort under låsen, før første mutation):
--   kanonisk(x)    følg samme_som (subjekt=alias → objekt=kanonisk, person/person) til sænken, dybde ≤ 20.
--   p39            SELECT DISTINCT person_id FROM public.person_external_id WHERE source_id=<manifestets source_id>.
--   tvilling       sorteret DISTINCT kanonisk(t2) over family_member t1 ⋈ t2 (samme familie, t2 partner, t2≠t1), hvor
--                  t1 er partner, t1.family_id ≠ family_id_1939, t1 ∉ p39 og kanonisk(t1)=kanonisk(hovedperson_id);
--                  = forventet_foer.tvilling_aegtefaeller = mulige_objekter.
--   alias urørt    ingen samme_som (nogen retning) med alias_person_id.
--   tekst_sha256   sha256 af kanonisk JSON {"klausuler":[…],"narrativ":tekst|null}: klausulerne er
--                  source_observation.verbatim_text for clauses[0] af hvert relation.marriage-element j i
--                  relation_persona_input(kilde), hvis hovedperson h_j = hovedperson_id og hvis marriage_ordinal IS NOT
--                  DISTINCT FROM hovedpersonens family_member.ordinal i family_id_1939, ordnet efter record_key (COLLATE
--                  "C", derefter elementets plads); narrativet er den første (ORDER BY id) person-narrativ for
--                  hovedpersonen i kilden. Kanonisk JSON = private.reimport_canonical_json_sha256 (= Pythons
--                  json.dumps(ensure_ascii=False, sort_keys=True, separators=(",",":")), UTF-8).
--   Desuden: hovedperson_kanonisk = kanonisk(hovedperson_id), hovedpersonen ∈ p39, og både hovedperson og alias er
--   partnere i family_id_1939.
--
-- Kvittering (vinduesvagten nøgler på den): pr. `S`-par en change_set uden hændelser, operation 'samme_som_kort_ceremoni',
-- kilden som subjekt, summary `T6D3_D_PAR kort=<kort> relation=<id> alias=<id> objekt=<id> retning=alias_objekt foer=0
-- change_set=<id>` (change_set = red_samme_som's eget sæt; foer = samme_som-kanter med aliaset før skrivningen). Til
-- sidst (også ved lutter I) én change_set uden hændelser med summary `T6D3_D_OK links=<n> ingen=<n>`. Uddata efter
-- COMMIT: parlinjerne i rækkefølge og så OK-linjen (kun nøgler, id'er og tal).
-- Fejlkoder: T6D3_PRE_* (intet skrevet), T6D3_POST_* (efterbetingelse; alt rulles tilbage).
--   PRE_ARGS/ROLE/GUC/TIMEOUT  argumenter, redaktionsrolle (via -v actor), aktiv change_set, 15 min-grænse
--   PRE_SHA       en fils sha afviger fra den GO-bundne, eller svarfilens manifest_sha256 ≠ manifestets sha
--   PRE_FASE      D's kvittering for kilden findes allerede (genkørsel)
--   PRE_SVAR      svarfilen: kontrakt, kort uden svar, ukendt kort, svar uden for svar_tilladt
--   PRE_MANIFEST  manifestets skema, eller en førtilstand afviger: fejlen nævner alle afvigende kort med årsag
--   POST_*        retning, sænke, kanttal, change_set
-- Brug: psql -X -At -v ON_ERROR_STOP=1 -v actor=<uuid> -v manifest_path=<fil> -v manifest_sha=<sha256>
--   -v svar_path=<fil> -v svar_sha=<sha256> -f samme_som_kort_ceremoni.sql
\set QUIET on
\set ON_ERROR_STOP on
\encoding UTF8
\set m `cat :'manifest_path'`
\set sv `cat :'svar_path'`
BEGIN;
SET LOCAL statement_timeout = '15min';
DO $timeout$ BEGIN IF current_setting('statement_timeout')<>'15min' THEN RAISE EXCEPTION 'T6D3_PRE_TIMEOUT'; END IF; END $timeout$;
SELECT set_config('request.jwt.claim.sub', :'actor', true), set_config('t6d3.manifest_sha', :'manifest_sha', true),
       set_config('t6d3.svar_sha', :'svar_sha', true) \g /dev/null
CREATE TEMP TABLE t6d3_input ON COMMIT DROP AS SELECT :'m'::text AS m_text, :'sv'::text AS sv_text;
CREATE TEMP TABLE t6d3_kort (ord integer PRIMARY KEY, kort text NOT NULL UNIQUE, handling text NOT NULL, k jsonb NOT NULL,
  svar text, objekt bigint) ON COMMIT DROP;
-- Uddata overlever COMMIT (ingen ON COMMIT DROP); psql-sessionen ender lige efter.
CREATE TEMP TABLE t6d3_ud (n serial PRIMARY KEY, linje text NOT NULL);

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

-- Kanonisk kort og kildens relationsinput fyldes under låsen (i $pre$).
CREATE TEMP TABLE t6d3_kanon (person_id bigint PRIMARY KEY, kanon bigint NOT NULL) ON COMMIT DROP;
CREATE TEMP TABLE t6d3_rpi (ord bigint PRIMARY KEY, record_key text, mord integer, tekst text, h bigint) ON COMMIT DROP;

DO $pre$
DECLARE v_src bigint; r record; v_why text[]; v_fejl text[]:='{}'; v_h bigint; v_fid bigint; v_alias bigint; v_ord integer;
  v_tvilling jsonb; v_sha text;
BEGIN
  IF current_setting('t6d3.manifest_sha') !~ '^[0-9a-f]{64}$' OR current_setting('t6d3.svar_sha') !~ '^[0-9a-f]{64}$'
     OR current_setting('request.jwt.claim.sub') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
    RAISE EXCEPTION 'T6D3_PRE_ARGS';
  END IF;
  IF public.current_rolle() IS DISTINCT FROM 'redaktion' THEN RAISE EXCEPTION 'T6D3_PRE_ROLE'; END IF;
  IF btrim(coalesce(current_setting('app.change_set_id',true),''))<>'' THEN RAISE EXCEPTION 'T6D3_PRE_GUC'; END IF;
  v_src:=pg_temp.t6d3_filer('T6D3');
  PERFORM set_config('t6d3.src',v_src::text,true);
  IF EXISTS (SELECT 1 FROM public.change_set WHERE operation='samme_som_kort_ceremoni' AND summary LIKE 'T6D3\_D\_OK %'
              AND subjekt_type='source' AND subjekt_id=v_src) THEN
    RAISE EXCEPTION 'T6D3_PRE_FASE';
  END IF;
  -- D-svarenes form: I eller S <et af mulige_objekter>; svar_tilladt rummer ikke andet.
  FOR r IN SELECT * FROM t6d3_kort WHERE handling='samme_som' ORDER BY ord LOOP
    IF jsonb_typeof(r.k->'mulige_objekter')<>'array'
       OR EXISTS (SELECT 1 FROM jsonb_array_elements_text(r.k->'svar_tilladt') t
                   WHERE t<>'I' AND NOT (t ~ '^S -?[0-9]+$' AND (r.k->'mulige_objekter') @> to_jsonb(ARRAY[substr(t,3)::bigint]))) THEN
      RAISE EXCEPTION 'T6D3_PRE_MANIFEST skema (kort %)',r.kort;
    END IF;
    IF r.svar ~ '^S -?[0-9]+$' THEN UPDATE t6d3_kort SET objekt=substr(r.svar,3)::bigint WHERE ord=r.ord;
    ELSIF r.svar<>'I' THEN RAISE EXCEPTION 'T6D3_PRE_SVAR kort %',r.kort; END IF;
  END LOOP;
  -- Lås: samme_som-mutationer serialiseres (re-entrant med red_samme_som's egen); kvitteringen efterprøves igen.
  PERFORM pg_advisory_xact_lock(hashtext('samme_som_mutation'));
  IF EXISTS (SELECT 1 FROM public.change_set WHERE operation='samme_som_kort_ceremoni' AND summary LIKE 'T6D3\_D\_OK %'
              AND subjekt_type='source' AND subjekt_id=v_src) THEN
    RAISE EXCEPTION 'T6D3_PRE_FASE';
  END IF;
  -- Kortets personer låses (alias, hovedperson og svarobjekt), så førtilstanden står til COMMIT.
  PERFORM 1 FROM public.person WHERE id IN (
      SELECT (k->>'alias_person_id')::bigint FROM t6d3_kort WHERE handling='samme_som' AND k->>'alias_person_id' ~ '^-?[0-9]+$'
      UNION SELECT (k->>'hovedperson_id')::bigint FROM t6d3_kort WHERE handling='samme_som' AND k->>'hovedperson_id' ~ '^-?[0-9]+$'
      UNION SELECT objekt FROM t6d3_kort WHERE objekt IS NOT NULL)
    ORDER BY id FOR UPDATE;
  -- Kanonisk kort og kildens relationsinput (én gang).
  INSERT INTO t6d3_kanon(person_id,kanon)
  -- BEGIN kanon (samme tekst i maal_trin6d3.sql; test_maal_trin6d3.py låser det)
  WITH RECURSIVE k(start,cur,d) AS (
    SELECT p.id,p.id,0 FROM public.person p
    UNION ALL
    SELECT k.start,ss.objekt_id,k.d+1 FROM k JOIN public.relation ss
        ON ss.rolle='samme_som' AND ss.subjekt_type='person' AND ss.objekt_type='person' AND ss.subjekt_id=k.cur
     WHERE k.d<20)
  SELECT DISTINCT ON (k.start) k.start AS person_id,k.cur AS kanon FROM k ORDER BY k.start,k.d DESC;
  -- END kanon
  INSERT INTO t6d3_rpi(ord,record_key,mord,tekst,h)
    SELECT x.ord,x.j->>'record_key' AS record_key,
           CASE WHEN x.j->>'marriage_ordinal' IS NULL THEN NULL ELSE (x.j->>'marriage_ordinal')::integer END AS mord,
           (SELECT o.verbatim_text FROM private.source_observation o WHERE o.id=(x.j#>>'{clauses,0,observation_id}')::uuid) AS tekst,
           (SELECT i.canonical_person_id FROM private.source_observation co
              JOIN private.source_mention sm ON sm.observation_id=co.parent_observation_id
              JOIN private.source_persona_mention spm ON spm.mention_id=sm.id AND spm.mention_role='primary'
              JOIN private.source_persona_identity i ON i.source_persona_id=spm.persona_id AND i.decision_status='accepted'
             WHERE co.id=(x.j#>>'{clauses,0,observation_id}')::uuid LIMIT 1) AS h
      FROM jsonb_array_elements(private.relation_persona_input(v_src)) WITH ORDINALITY AS x(j,ord)
     WHERE x.j->>'predicate'='relation.marriage';
  -- Førtilstanden for hvert D-kort; alle afvigelser samles.
  FOR r IN SELECT * FROM t6d3_kort WHERE handling='samme_som' ORDER BY ord LOOP
    v_why:='{}';
    IF coalesce(r.k->>'hovedperson_id','') !~ '^-?[0-9]+$' OR coalesce(r.k->>'alias_person_id','') !~ '^-?[0-9]+$'
       OR coalesce(r.k->>'family_id_1939','') !~ '^-?[0-9]+$' OR coalesce(r.k->>'hovedperson_kanonisk','') !~ '^-?[0-9]+$'
       OR jsonb_typeof(r.k#>'{forventet_foer,tvilling_aegtefaeller}')<>'array'
       OR jsonb_typeof(r.k#>'{forventet_foer,alias_samme_som}')<>'boolean' THEN
      v_fejl:=v_fejl||format('%s (skema)',r.kort); CONTINUE;
    END IF;
    v_h:=(r.k->>'hovedperson_id')::bigint; v_alias:=(r.k->>'alias_person_id')::bigint; v_fid:=(r.k->>'family_id_1939')::bigint;
    IF NOT EXISTS (SELECT 1 FROM public.person_external_id WHERE source_id=v_src AND person_id=v_h) THEN v_why:=v_why||'p39'::text; END IF;
    IF (SELECT kanon FROM t6d3_kanon WHERE person_id=v_h) IS DISTINCT FROM (r.k->>'hovedperson_kanonisk')::bigint THEN
      v_why:=v_why||'kanonisk'::text; END IF;
    SELECT fm.ordinal INTO v_ord FROM public.family_member fm WHERE fm.family_id=v_fid AND fm.person_id=v_h AND fm.rolle='partner';
    IF NOT FOUND OR NOT EXISTS (SELECT 1 FROM public.family_member fm WHERE fm.family_id=v_fid AND fm.person_id=v_alias AND fm.rolle='partner')
       OR v_alias=v_h THEN
      v_why:=v_why||'familie'::text;
    END IF;
    -- Aliaset er urørt.
    IF (r.k#>>'{forventet_foer,alias_samme_som}')::boolean
       OR EXISTS (SELECT 1 FROM public.relation WHERE rolle='samme_som' AND subjekt_type='person' AND objekt_type='person'
                   AND (subjekt_id=v_alias OR objekt_id=v_alias)) THEN
      v_why:=v_why||'alias'::text;
    END IF;
    -- Tvillingens ægtefællemængde.
    SELECT coalesce(jsonb_agg(DISTINCT k2.kanon ORDER BY k2.kanon),'[]'::jsonb) INTO v_tvilling
      FROM public.family_member t1
      JOIN public.family_member t2 ON t2.family_id=t1.family_id AND t2.rolle='partner' AND t2.person_id<>t1.person_id
      JOIN t6d3_kanon k1 ON k1.person_id=t1.person_id
      JOIN t6d3_kanon k2 ON k2.person_id=t2.person_id
     WHERE t1.rolle='partner' AND t1.family_id<>v_fid
       AND t1.person_id NOT IN (SELECT DISTINCT e.person_id FROM public.person_external_id e WHERE e.source_id=v_src AND e.person_id IS NOT NULL)
       AND k1.kanon=(SELECT kanon FROM t6d3_kanon WHERE person_id=v_h);
    IF v_tvilling IS DISTINCT FROM r.k#>'{forventet_foer,tvilling_aegtefaeller}' OR v_tvilling IS DISTINCT FROM r.k->'mulige_objekter' THEN
      v_why:=v_why||'tvilling'::text;
    END IF;
    -- Kortets tekst.
    v_sha:=private.reimport_canonical_json_sha256(jsonb_build_object(
      'klausuler',coalesce((SELECT jsonb_agg(to_jsonb(x.tekst) ORDER BY x.record_key COLLATE "C",x.ord)
                              FROM t6d3_rpi x WHERE x.h=v_h AND x.mord IS NOT DISTINCT FROM v_ord),'[]'::jsonb),
      'narrativ',(SELECT to_jsonb(n.tekst) FROM public.narrative n
                   WHERE n.subjekt_type='person' AND n.subjekt_id=v_h AND n.source_id=v_src ORDER BY n.id LIMIT 1)));
    IF v_sha IS DISTINCT FROM r.k->>'tekst_sha256' THEN v_why:=v_why||'tekst'::text; END IF;
    -- Svarobjektet er stadig en sænke (mulige_objekter er kanoniske).
    IF r.objekt IS NOT NULL AND (SELECT kanon FROM t6d3_kanon WHERE person_id=r.objekt) IS DISTINCT FROM r.objekt THEN
      v_why:=v_why||'objekt'::text;
    END IF;
    IF cardinality(v_why)>0 THEN v_fejl:=v_fejl||format('%s (%s)',r.kort,array_to_string(v_why,',')); END IF;
  END LOOP;
  IF cardinality(v_fejl)>0 THEN RAISE EXCEPTION 'T6D3_PRE_MANIFEST kort %',array_to_string(v_fejl,', '); END IF;
END $pre$;

DO $write$
DECLARE v_src bigint:=current_setting('t6d3.src')::bigint; r record; v_rel bigint; v_cs text; v_links integer:=0;
  v_ingen integer; v_foer integer; v_kanter_foer bigint; v_rcs bigint; v_kanon bigint;
BEGIN
  v_kanter_foer:=(SELECT count(*) FROM public.relation WHERE rolle='samme_som' AND subjekt_type='person' AND objekt_type='person');
  FOR r IN SELECT * FROM t6d3_kort WHERE handling='samme_som' AND objekt IS NOT NULL ORDER BY ord LOOP
    v_foer:=(SELECT count(*) FROM public.relation WHERE rolle='samme_som' AND subjekt_type='person' AND objekt_type='person'
               AND (subjekt_id=(r.k->>'alias_person_id')::bigint OR objekt_id=(r.k->>'alias_person_id')::bigint));
    PERFORM set_config('app.change_set_id','',true);
    v_rel:=public.red_samme_som((r.k->>'alias_person_id')::bigint,r.objekt);
    v_cs:=current_setting('app.change_set_id',true);
    PERFORM set_config('app.change_set_id','',true);
    -- Faktisk retning: kortets 1939-række er alias, svarobjektet kanonisk; begge har nu svarobjektets sænke.
    IF NOT EXISTS (SELECT 1 FROM public.relation WHERE id=v_rel AND rolle='samme_som' AND subjekt_type='person' AND objekt_type='person'
                    AND subjekt_id=(r.k->>'alias_person_id')::bigint AND objekt_id=r.objekt) THEN
      RAISE EXCEPTION 'T6D3_POST_RETNING kort %',r.kort;
    END IF;
    IF coalesce(v_cs,'') !~ '^[0-9]+$' OR NOT EXISTS (SELECT 1 FROM public.change_set WHERE id=v_cs::bigint AND operation='red_samme_som') THEN
      RAISE EXCEPTION 'T6D3_POST_CHANGE_SET kort %',r.kort;
    END IF;
    WITH RECURSIVE k(cur,d) AS (
      SELECT (r.k->>'alias_person_id')::bigint,0
      UNION ALL
      SELECT x.objekt_id,k.d+1 FROM k JOIN public.relation x
          ON x.rolle='samme_som' AND x.subjekt_type='person' AND x.objekt_type='person' AND x.subjekt_id=k.cur WHERE k.d<20)
    SELECT cur INTO v_kanon FROM k ORDER BY d DESC LIMIT 1;
    IF v_kanon IS DISTINCT FROM r.objekt
       OR EXISTS (SELECT 1 FROM public.relation WHERE rolle='samme_som' AND subjekt_type='person' AND objekt_type='person' AND subjekt_id=r.objekt) THEN
      RAISE EXCEPTION 'T6D3_POST_SAENKE kort %',r.kort;
    END IF;
    v_rcs:=public.begin_change_set('samme_som_kort_ceremoni',
      format('T6D3_D_PAR kort=%s relation=%s alias=%s objekt=%s retning=alias_objekt foer=%s change_set=%s',
             r.kort,v_rel,r.k->>'alias_person_id',r.objekt,v_foer,v_cs),'source',v_src);
    PERFORM set_config('app.change_set_id','',true);
    INSERT INTO t6d3_ud(linje) SELECT summary FROM public.change_set WHERE id=v_rcs;
    v_links:=v_links+1;
  END LOOP;
  v_ingen:=(SELECT count(*) FROM t6d3_kort WHERE handling='samme_som' AND svar='I');
  -- Efterbetingelser: præcis én ny kant pr. S; I-kortenes aliaser er stadig urørte.
  IF (SELECT count(*) FROM public.relation WHERE rolle='samme_som' AND subjekt_type='person' AND objekt_type='person')<>v_kanter_foer+v_links THEN
    RAISE EXCEPTION 'T6D3_POST_KANTER';
  END IF;
  IF EXISTS (SELECT 1 FROM t6d3_kort c JOIN public.relation x ON x.rolle='samme_som' AND x.subjekt_type='person' AND x.objekt_type='person'
                AND (x.subjekt_id=(c.k->>'alias_person_id')::bigint OR x.objekt_id=(c.k->>'alias_person_id')::bigint)
              WHERE c.handling='samme_som' AND c.svar='I') THEN
    RAISE EXCEPTION 'T6D3_POST_INGEN';
  END IF;
  IF btrim(coalesce(current_setting('app.change_set_id',true),''))<>'' THEN RAISE EXCEPTION 'T6D3_POST_GUC'; END IF;
  v_rcs:=public.begin_change_set('samme_som_kort_ceremoni',format('T6D3_D_OK links=%s ingen=%s',v_links,v_ingen),'source',v_src);
  PERFORM set_config('app.change_set_id','',true);
  INSERT INTO t6d3_ud(linje) SELECT summary FROM public.change_set WHERE id=v_rcs;
END $write$;
COMMIT;
SELECT linje FROM t6d3_ud ORDER BY n;
