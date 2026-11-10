-- Trin 6d-2a (plan Task 6): identitets-ceremonien for én kilde. I ÉN transaktion anvendes de menneskeligt godkendte
-- kort: pr. kort med svaret J (kandidaten) eller A <person> (en anden person) enten en samme_som-kobling
-- (red_samme_som) eller en kildepersona-identitet (red_afgoer_source_persona, 'same', basis human_sheet); et N skriver
-- intet for kortet. Kildeparametriseret; nævner hverken udgaver, kilde-id'er eller person-id'er i logikken.
-- Kvittering: en change_set uden hændelser, skrevet SIDST (også ved nul skrivninger):
--   operation 'identitet_ceremoni' med kilden som subjekt (subjekt_type 'source'; PRE_FASE og målingens fase=data filtrerer på den), summary `T6D2A_OK kanter=<n> identiteter=<n> regel=<n>`; ceremonien udskriver samme linje.
-- Fejlkoder: T6D2A_PRE_* (intet skrevet), T6D2A_POST_* (efterbetingelser; alt rulles tilbage). Alle fejl ruller hele
-- transaktionen tilbage.
--   PRE_ARGS/TIMEOUT/ROLE/DDL/GUC  argumenter, 15 min-grænse, redaktionsrolle (via -v actor), DDL fra Task 3-5, ingen
--                                  aktiv change_set
--   PRE_FASE      kvitteringen findes allerede (genkørsel)
--   PRE_SHA       manifestets eller svarfilens sha afviger fra den GO-bundne; manifestets svar_sha256 ≠ svarfilens sha
--   PRE_SVAR      svarfilen: ikke ét svar pr. manifestkort, ukendt kort, dublet, A uden person-id
--   PRE_MANIFEST  en førtilstand afviger fra manifestet (efterprøvet under lås): kontrakt/kilde, version, status,
--                 persona_key/source_id, staged, eksisterende kant, tekst-sha'er, kandidatens subjekt, A-personen findes ikke
--   POST_*        FAKTA, KOORD_2018_20, regel, unresolved/uden_identitet, kvitteringens tal
-- Filerne indlæses klientside (\set … `cat`), aldrig \copy; psql's backtick fjerner én afsluttende linjeskift, så de
-- bundne sha'er accepteres både med og uden den (som placement_ceremoni.sql). Ceremonien genberegner ikke filernes sha
-- ud over denne sammenligning; runneren giver de GO-bundne.
--   manifest  trin6d2a-kortmanifest-v1: {contract, source_id, kort_html_sha256, svar_sha256, kort:[{kort, linje, handling
--             samme_som|identitet, (alias_person_id, objekt_person_id) | (source_persona_id, persona_key),
--             forventet_foer{samme_som_kant, staged | identitet_status, identitet_version}, kandidat{person_id,
--             narrative_id, side, tekst_sha256}, oversigt{…}}]}. Hashes: sha256 hex over UTF-8 af narrative.tekst
--             (kandidat.tekst_sha256, oversigt.tekst_sha256 og kontekst_tekst_sha256 for samme_som-kort) eller af
--             source_mention.verbatim_text for personaens mention med ordinal=1 (identitetskortenes
--             oversigt.mention_sha256 og tekst_sha256). staged = aliasets person.staged.
--   svar      ren tekst: `#`-kommentarer; ellers én linje pr. kort `<kort> <J|N|A person-id>` evt. efterfulgt af # …
-- Brug: psql -X -At -v ON_ERROR_STOP=1 -v actor=<uuid> -v src=<kilde> -v manifest_path=<fil> -v manifest_sha=<sha256>
--   -v svar_path=<fil> -v svar_sha=<GO-bundet sha256> -v expect_kanter=N -v expect_identiteter=N -v expect_regel=N
--   -f identitet_ceremoni.sql
-- expect_kanter/identiteter = antal J/A-kort af hver slags; expect_regel = antal rækker reglen giver for alle personer
-- efter ceremonien.
\set QUIET on
\set ON_ERROR_STOP on
\set m `cat :'manifest_path'`
\set sv `cat :'svar_path'`
BEGIN;
SET LOCAL statement_timeout = '15min';
DO $timeout$ BEGIN IF current_setting('statement_timeout')<>'15min' THEN RAISE EXCEPTION 'T6D2A_PRE_TIMEOUT'; END IF; END $timeout$;
SELECT set_config('request.jwt.claim.sub', :'actor', true), set_config('t6.src', :'src', true),
       set_config('t6.manifest_sha', :'manifest_sha', true), set_config('t6.svar_sha', :'svar_sha', true),
       set_config('t6.expect_kanter', :'expect_kanter', true), set_config('t6.expect_identiteter', :'expect_identiteter', true),
       set_config('t6.expect_regel', :'expect_regel', true) \g /dev/null
CREATE TEMP TABLE t6_input ON COMMIT DROP AS SELECT :'m'::text AS m_text, :'sv'::text AS sv_text;
-- Ét kort pr. række: manifestets kort, svaret og den person, der skrives mod (kandidaten ved J, svarpersonen ved A).
CREATE TEMP TABLE t6_kort (ord integer PRIMARY KEY, kort text NOT NULL UNIQUE, handling text NOT NULL, k jsonb NOT NULL,
  svar text NOT NULL, svar_person bigint, person bigint) ON COMMIT DROP;

CREATE FUNCTION pg_temp.t6_sha(p_text text) RETURNS text LANGUAGE sql IMMUTABLE AS
  $f$ SELECT encode(sha256(convert_to(p_text,'UTF8')),'hex') $f$;

-- Koordinat-hash (samme udtryk som maal_trin6d2a.sql): p_andre = rækkerne med source_id <> kilden, ellers kildens egne.
CREATE FUNCTION pg_temp.t6_koord(p_src bigint,p_andre boolean) RETURNS text LANGUAGE sql AS $f$
  SELECT md5(coalesce(string_agg(concat_ws('|',quote_nullable(c.person_id),quote_nullable(c.source_id),
           quote_nullable(c.legacy_line_code),quote_nullable(c.printed_number),quote_nullable(c.printed_number_label),
           quote_nullable(c.generation_local),quote_nullable(c.generation_global),quote_nullable(c.kuld_label),
           quote_nullable(c.provenance_kind)),E'\n' ORDER BY c.person_id,c.source_id),''))
    FROM public.public_person_source_coordinates() c
   WHERE (c.source_id<>p_src)=p_andre;
$f$;

-- FAKTA (samme udtryk som maal_trin6d2a.sql): public_person_facts + public_family_sources for alle offentlige personer,
-- beregnet som anon.
CREATE FUNCTION pg_temp.t6_fakta() RETURNS text LANGUAGE plpgsql AS $f$
DECLARE v_ids bigint[]; v_fids bigint[]; v text;
BEGIN
  v_ids:=ARRAY(SELECT id FROM public.person WHERE public.person_offentlig(id) ORDER BY id);
  v_fids:=ARRAY(SELECT id FROM public.family ORDER BY id);
  SET LOCAL ROLE anon;
  SELECT md5(coalesce(string_agg(x,E'\n' ORDER BY x COLLATE "C"),'')) INTO v
    FROM (SELECT 'f|'||f::text AS x FROM public.public_person_facts(v_ids) f
          UNION ALL
          SELECT 's|'||s::text FROM public.public_family_sources(v_fids) s) z;
  RESET ROLE;
  RETURN v;
END $f$;

-- Førtilstanden for ét kort (efterprøvet under lås): NULL = i orden, ellers årsagen (uden id'er og tekst).
CREATE FUNCTION pg_temp.t6_tjek(p_k jsonb,p_svar text,p_person bigint) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE v_src bigint:=current_setting('t6.src')::bigint; v_h text:=p_k->>'handling'; v_alias bigint; v_obj bigint;
  v_p uuid; v_st text; v_ver integer; v_n record; v_kant boolean; v_staged boolean; v_x text; v_m text;
  v_cand bigint:=(p_k#>>'{kandidat,person_id}')::bigint;
BEGIN
  IF jsonb_typeof(p_k->'kandidat')<>'object' OR jsonb_typeof(p_k->'oversigt')<>'object'
     OR jsonb_typeof(p_k->'forventet_foer')<>'object'
     OR coalesce(p_k#>>'{kandidat,tekst_sha256}','') !~ '^[0-9a-f]{64}$' THEN RETURN 'skema'; END IF;
  -- Kandidaten (ved J): personen findes, narrativen er hans/hendes i kilden, og teksten har den viste sha.
  -- Ved A efterprøves kandidatens tekst ikke; svarpersonen skal findes.
  IF p_svar='A' THEN
    IF NOT EXISTS (SELECT 1 FROM public.person WHERE id=p_person) THEN RETURN 'svarperson findes ikke'; END IF;
  ELSE
    IF v_cand IS NULL OR v_cand<>p_person OR NOT EXISTS (SELECT 1 FROM public.person WHERE id=v_cand) THEN
      RETURN 'kandidatperson'; END IF;
    SELECT n.subjekt_type,n.subjekt_id,n.source_id,pg_temp.t6_sha(n.tekst) AS sha INTO v_n
      FROM public.narrative n WHERE n.id=(p_k#>>'{kandidat,narrative_id}')::bigint;
    IF v_n IS NULL OR v_n.subjekt_type<>'person' OR v_n.subjekt_id<>v_cand OR v_n.source_id<>v_src
       OR v_n.sha IS DISTINCT FROM p_k#>>'{kandidat,tekst_sha256}' THEN RETURN 'kandidattekst'; END IF;
  END IF;
  IF v_h='samme_som' THEN
    v_alias:=(p_k->>'alias_person_id')::bigint;
    -- Ved A er objektet svarpersonen (det er dét par, der skrives), ellers manifestets objekt.
    v_obj:=CASE WHEN p_svar='A' THEN p_person ELSE (p_k->>'objekt_person_id')::bigint END;
    IF v_alias IS NULL OR v_obj IS NULL OR v_alias=v_obj THEN RETURN 'kobling'; END IF;
    IF p_svar<>'A' AND v_obj<>v_cand THEN RETURN 'objekt er ikke kandidaten'; END IF;
    SELECT staged INTO v_staged FROM public.person WHERE id=v_alias;
    IF NOT FOUND OR NOT EXISTS (SELECT 1 FROM public.person WHERE id=v_obj) THEN RETURN 'person findes ikke'; END IF;
    IF coalesce(v_staged,false) IS DISTINCT FROM (p_k#>>'{forventet_foer,staged}')::boolean THEN RETURN 'staged'; END IF;
    v_kant:=EXISTS (SELECT 1 FROM public.relation WHERE rolle='samme_som' AND subjekt_type='person' AND objekt_type='person'
                      AND ((subjekt_id=v_alias AND objekt_id=v_obj) OR (subjekt_id=v_obj AND objekt_id=v_alias)));
    IF v_kant IS DISTINCT FROM (p_k#>>'{forventet_foer,samme_som_kant}')::boolean OR v_kant THEN RETURN 'kant'; END IF;
    -- Oversigtsomtalen og dens kontekst: de viste tekster er uændrede.
    IF NOT EXISTS (SELECT 1 FROM public.narrative n WHERE n.id=(p_k#>>'{oversigt,narrative_id}')::bigint
                      AND n.subjekt_type='person' AND n.subjekt_id=v_alias AND n.source_id=v_src
                      AND pg_temp.t6_sha(n.tekst)=p_k#>>'{oversigt,tekst_sha256}') THEN RETURN 'oversigtstekst'; END IF;
    IF NOT EXISTS (SELECT 1 FROM public.narrative n WHERE n.id=(p_k#>>'{oversigt,kontekst_narrative_id}')::bigint
                      AND n.subjekt_type='person' AND n.source_id=v_src
                      AND pg_temp.t6_sha(n.tekst)=p_k#>>'{oversigt,kontekst_tekst_sha256}') THEN RETURN 'kontekst'; END IF;
  ELSIF v_h='identitet' THEN
    IF coalesce(p_k->>'source_persona_id','') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
      RETURN 'persona-id'; END IF;
    v_p:=(p_k->>'source_persona_id')::uuid;
    IF NOT EXISTS (SELECT 1 FROM private.source_persona WHERE id=v_p AND source_id=v_src AND persona_key=p_k->>'persona_key') THEN
      RETURN 'persona'; END IF;
    SELECT i.decision_status,i.version INTO v_st,v_ver FROM private.source_persona_identity i WHERE i.source_persona_id=v_p;
    IF (p_k#>>'{forventet_foer,identitet_status}') IS DISTINCT FROM v_st
       OR coalesce((p_k#>>'{forventet_foer,identitet_version}')::integer,-1) IS DISTINCT FROM coalesce(v_ver,0) THEN
      RETURN 'identitet'; END IF;
    SELECT pg_temp.t6_sha(sm.verbatim_text) INTO v_m FROM private.source_persona_mention spm
      JOIN private.source_mention sm ON sm.id=spm.mention_id WHERE spm.persona_id=v_p AND spm.ordinal=1;
    IF v_m IS DISTINCT FROM p_k#>>'{oversigt,mention_sha256}' OR v_m IS DISTINCT FROM p_k#>>'{oversigt,tekst_sha256}' THEN
      RETURN 'oversigtstekst'; END IF;
  ELSE RETURN 'handling'; END IF;
  RETURN NULL;
END $f$;

DO $pre$
DECLARE v_src bigint:=current_setting('t6.src')::bigint; v_msha text:=current_setting('t6.manifest_sha');
  v_ssha text:=current_setting('t6.svar_sha'); i t6_input%ROWTYPE; m jsonb; v_k jsonb; r record; g text[]; v_why text;
  v_ord integer:=0; v_n integer;
BEGIN
  IF v_msha !~ '^[0-9a-f]{64}$' OR v_ssha !~ '^[0-9a-f]{64}$'
     OR current_setting('t6.expect_kanter') !~ '^[0-9]+$' OR current_setting('t6.expect_identiteter') !~ '^[0-9]+$'
     OR current_setting('t6.expect_regel') !~ '^[0-9]+$' THEN RAISE EXCEPTION 'T6D2A_PRE_ARGS'; END IF;
  IF public.current_rolle() IS DISTINCT FROM 'redaktion' THEN RAISE EXCEPTION 'T6D2A_PRE_ROLE'; END IF;
  IF to_regprocedure('private.overview_mention_narratives(bigint[])') IS NULL
     OR to_regprocedure('private.samme_som_data_direction(bigint,bigint)') IS NULL
     OR coalesce(position('samme_som_data_direction' IN (SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('public.red_samme_som(bigint,bigint)')))>0,false) IS NOT TRUE
     OR coalesce(position('overview_mention_narratives' IN (SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('public.public_person_bio_source_versions_v2(bigint[])')))>0,false) IS NOT TRUE THEN
    RAISE EXCEPTION 'T6D2A_PRE_DDL';
  END IF;
  IF btrim(coalesce(current_setting('app.change_set_id',true),''))<>'' THEN RAISE EXCEPTION 'T6D2A_PRE_GUC'; END IF;
  -- Fase: kvitteringen findes ikke (genkørsel stopper her; en kørsel med fire N skriver også kvitteringen).
  IF EXISTS (SELECT 1 FROM public.change_set WHERE operation='identitet_ceremoni' AND summary LIKE 'T6D2A\_OK %'
              AND subjekt_type='source' AND subjekt_id=v_src) THEN
    RAISE EXCEPTION 'T6D2A_PRE_FASE';
  END IF;
  -- Filerne er de GO-bundne (psql's `cat` fjerner én afsluttende linjeskift).
  SELECT * INTO i FROM t6_input;
  IF v_msha NOT IN (pg_temp.t6_sha(i.m_text),pg_temp.t6_sha(i.m_text||E'\n'))
     OR v_ssha NOT IN (pg_temp.t6_sha(i.sv_text),pg_temp.t6_sha(i.sv_text||E'\n')) THEN
    RAISE EXCEPTION 'T6D2A_PRE_SHA';
  END IF;
  BEGIN m:=i.m_text::jsonb; EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'T6D2A_PRE_MANIFEST skema'; END;
  IF m->>'svar_sha256' IS DISTINCT FROM v_ssha THEN RAISE EXCEPTION 'T6D2A_PRE_SHA'; END IF;
  IF m->>'contract' IS DISTINCT FROM 'trin6d2a-kortmanifest-v1' OR (m->>'source_id') IS DISTINCT FROM v_src::text
     OR coalesce(m->>'kort_html_sha256','') !~ '^[0-9a-f]{64}$' OR jsonb_typeof(m->'kort')<>'array'
     OR jsonb_array_length(m->'kort')=0 THEN
    RAISE EXCEPTION 'T6D2A_PRE_MANIFEST kontrakt';
  END IF;
  FOR v_k IN SELECT x FROM jsonb_array_elements(m->'kort') x LOOP
    v_ord:=v_ord+1;
    IF jsonb_typeof(v_k)<>'object' OR coalesce(v_k->>'kort','')='' OR coalesce(v_k->>'handling','') NOT IN ('samme_som','identitet')
       OR coalesce(v_k->>'linje','') !~ '^[1-9][0-9]*$' THEN
      RAISE EXCEPTION 'T6D2A_PRE_MANIFEST skema (kort nr. %)',v_ord;
    END IF;
    IF EXISTS (SELECT 1 FROM t6_kort WHERE kort=v_k->>'kort') THEN RAISE EXCEPTION 'T6D2A_PRE_MANIFEST dublet %',v_k->>'kort'; END IF;
    INSERT INTO t6_kort(ord,kort,handling,k,svar) VALUES (v_ord,v_k->>'kort',v_k->>'handling',v_k,'?');
  END LOOP;
  -- Svarene: ét pr. manifestkort.
  FOR r IN SELECT btrim(regexp_replace(l.line,'#.*$','')) AS ln,l.ord FROM
           unnest(string_to_array(replace(i.sv_text,E'\r',''),E'\n')) WITH ORDINALITY AS l(line,ord) LOOP
    IF r.ln='' THEN CONTINUE; END IF;
    g:=regexp_match(r.ln,'^([^[:space:]]+)[[:space:]]+([JNA])(?:[[:space:]]+(-?[0-9]+))?$');
    IF g IS NULL OR (g[2]='A')<>(g[3] IS NOT NULL) THEN RAISE EXCEPTION 'T6D2A_PRE_SVAR linje %',r.ord; END IF;
    UPDATE t6_kort SET svar=g[2],svar_person=g[3]::bigint WHERE kort=g[1] AND svar='?';
    IF NOT FOUND THEN RAISE EXCEPTION 'T6D2A_PRE_SVAR ukendt eller dobbelt kort (linje %)',r.ord; END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM t6_kort WHERE svar='?') THEN RAISE EXCEPTION 'T6D2A_PRE_SVAR kort uden svar'; END IF;
  UPDATE t6_kort SET person=CASE svar WHEN 'A' THEN svar_person ELSE (k#>>'{kandidat,person_id}')::bigint END;
  -- Lås-rækkefølge: advisory → source_persona → source_persona_identity → person, som red_afgoer_source_persona
  -- (persona → identitet → person); personrækkerne låses stadig før staged-tjekket.
  PERFORM pg_advisory_xact_lock(hashtext('samme_som_mutation'));
  -- Kvitteringen efterprøves igen under låsen (en samtidig ceremoni kan have committet siden første tjek).
  IF EXISTS (SELECT 1 FROM public.change_set WHERE operation='identitet_ceremoni' AND summary LIKE 'T6D2A\_OK %'
              AND subjekt_type='source' AND subjekt_id=v_src) THEN
    RAISE EXCEPTION 'T6D2A_PRE_FASE';
  END IF;
  PERFORM 1 FROM private.source_persona
    WHERE id IN (SELECT (k->>'source_persona_id')::uuid FROM t6_kort WHERE handling='identitet'
                    AND k->>'source_persona_id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') FOR UPDATE;
  PERFORM 1 FROM private.source_persona_identity
    WHERE source_persona_id IN (SELECT (k->>'source_persona_id')::uuid FROM t6_kort WHERE handling='identitet'
                                   AND k->>'source_persona_id' ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') FOR UPDATE;
  -- Personrækkerne (alias + objekt for samme_som-kortene) låses, så staged-tjekket i t6_tjek ikke kan ændre sig før COMMIT.
  PERFORM 1 FROM public.person
    WHERE id IN (SELECT (k->>'alias_person_id')::bigint FROM t6_kort WHERE handling='samme_som' AND k->>'alias_person_id' IS NOT NULL
                 UNION SELECT person FROM t6_kort WHERE handling='samme_som' AND person IS NOT NULL)
    ORDER BY id FOR UPDATE;
  -- Førtilstanden for hvert kort (også N-kort: manifestet er ét øjebliksbillede).
  FOR r IN SELECT * FROM t6_kort ORDER BY ord LOOP
    v_why:=pg_temp.t6_tjek(r.k,r.svar,r.person);
    IF v_why IS NOT NULL THEN RAISE EXCEPTION 'T6D2A_PRE_MANIFEST kort % (%)',r.kort,v_why; END IF;
  END LOOP;
END $pre$;

DO $write$
DECLARE v_src bigint:=current_setting('t6.src')::bigint; v_msha text:=current_setting('t6.manifest_sha');
  v_ssha text:=current_setting('t6.svar_sha'); r record; v_k_foer text; v_f_foer text; v_ver integer;
  v_kanter integer:=0; v_ident integer:=0; v_regel integer; v_unres integer; v_uden integer; v_cs bigint;
  v_exp_unres integer; v_exp_uden integer; v_alias bigint; v_obj bigint;
BEGIN
  v_k_foer:=pg_temp.t6_koord(v_src,true);
  v_f_foer:=pg_temp.t6_fakta();
  FOR r IN SELECT * FROM t6_kort WHERE svar IN ('J','A') ORDER BY ord LOOP
    PERFORM set_config('app.change_set_id','',true);
    IF r.handling='samme_som' THEN
      v_alias:=(r.k->>'alias_person_id')::bigint; v_obj:=r.person;
      PERFORM public.red_samme_som(v_alias,v_obj);
      PERFORM set_config('app.change_set_id','',true);
      IF NOT EXISTS (SELECT 1 FROM public.relation WHERE rolle='samme_som' AND subjekt_type='person' AND objekt_type='person'
                      AND ((subjekt_id=v_alias AND objekt_id=v_obj) OR (subjekt_id=v_obj AND objekt_id=v_alias))) THEN
        RAISE EXCEPTION 'T6D2A_POST_KANT kort %',r.kort;
      END IF;
      v_kanter:=v_kanter+1;
    ELSE
      v_ver:=public.red_afgoer_source_persona((r.k->>'source_persona_id')::uuid,
        coalesce((r.k#>>'{forventet_foer,identitet_version}')::integer,0),'same',r.person,
        format('identitetskort %s (%s)',r.kort,r.svar),
        jsonb_build_object('basis','human_sheet','sheet_sha256',v_msha,'rows_sha256',v_ssha,'line',(r.k->>'linje')::integer));
      PERFORM set_config('app.change_set_id','',true);
      IF v_ver IS DISTINCT FROM coalesce((r.k#>>'{forventet_foer,identitet_version}')::integer,0)+1
         OR NOT EXISTS (SELECT 1 FROM private.source_persona_identity i WHERE i.source_persona_id=(r.k->>'source_persona_id')::uuid
                          AND i.decision_status='accepted' AND i.canonical_person_id=r.person AND i.version=v_ver) THEN
        RAISE EXCEPTION 'T6D2A_POST_IDENTITET kort %',r.kort;
      END IF;
      v_ident:=v_ident+1;
    END IF;
  END LOOP;
  -- Efterbetingelser. unresolved/uden_identitet = 0 bortset fra de registrerede N.
  SELECT count(*) FILTER (WHERE i.decision_status='unresolved'),count(*) FILTER (WHERE i.source_persona_id IS NULL)
    INTO v_unres,v_uden FROM private.source_persona sp
    LEFT JOIN private.source_persona_identity i ON i.source_persona_id=sp.id WHERE sp.source_id=v_src;
  SELECT count(*) FILTER (WHERE k#>>'{forventet_foer,identitet_status}'='unresolved'),
         count(*) FILTER (WHERE k#>>'{forventet_foer,identitet_status}' IS NULL)
    INTO v_exp_unres,v_exp_uden FROM t6_kort WHERE handling='identitet' AND svar='N';
  IF v_unres<>v_exp_unres OR v_uden<>v_exp_uden THEN
    RAISE EXCEPTION 'T6D2A_POST_IDENTITETER unresolved=% (forventet %) uden_identitet=% (forventet %)',v_unres,v_exp_unres,v_uden,v_exp_uden;
  END IF;
  IF pg_temp.t6_koord(v_src,true) IS DISTINCT FROM v_k_foer THEN RAISE EXCEPTION 'T6D2A_POST_KOORD'; END IF;
  IF pg_temp.t6_fakta() IS DISTINCT FROM v_f_foer THEN RAISE EXCEPTION 'T6D2A_POST_FAKTA'; END IF;
  v_regel:=(SELECT count(*) FROM private.overview_mention_narratives(ARRAY(SELECT id FROM public.person)));
  IF v_regel<>current_setting('t6.expect_regel')::integer THEN
    RAISE EXCEPTION 'T6D2A_POST_REGEL regel=% (forventet %)',v_regel,current_setting('t6.expect_regel');
  END IF;
  IF v_kanter<>current_setting('t6.expect_kanter')::integer OR v_ident<>current_setting('t6.expect_identiteter')::integer THEN
    RAISE EXCEPTION 'T6D2A_POST_KVITTERING kanter=% (forventet %) identiteter=% (forventet %)',v_kanter,
      current_setting('t6.expect_kanter'),v_ident,current_setting('t6.expect_identiteter');
  END IF;
  -- Kvitteringen skrives sidst: en change_set uden hændelser (også ved nul skrivninger).
  IF btrim(coalesce(current_setting('app.change_set_id',true),''))<>'' THEN RAISE EXCEPTION 'T6D2A_POST_GUC'; END IF;
  v_cs:=public.begin_change_set('identitet_ceremoni',format('T6D2A_OK kanter=%s identiteter=%s regel=%s',v_kanter,v_ident,v_regel),
    'source',v_src);
  PERFORM set_config('app.change_set_id','',true);
END $write$;
COMMIT;
SELECT summary FROM public.change_set WHERE operation='identitet_ceremoni' AND summary LIKE 'T6D2A\_OK %'
   AND subjekt_type='source' AND subjekt_id=:src ORDER BY id DESC LIMIT 1;
