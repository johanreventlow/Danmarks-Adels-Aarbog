-- Trin 6e-2 (plan Task 9): dataceremonien for læsbare postetiketter, kildens sidekort og linjeskemaets rettede navne.
-- I ÉN transaktion: kildens sidekort, linjeskemaets etiketrettelser, de publicerede bindingers record_label og
-- citation_label (fra private.narrative_record_wanted_labels) for poster uden bogtrykt nøgle (etiket ~ '^record-'),
-- og revalidering af kildens bindinger, der derved bliver `stale_published`, så læseren aldrig ser dem forældede.
-- Kildeparametriseret; nævner ingen udgave. Ingen påstand, konklusion, citation eller narrative.side ændres.
-- Fejlkoder ETK_PRE_* (intet skrevet), ETK_MID_* (under skrivningen), ETK_POST_* (efterbetingelser); enhver fejl
-- ruller hele transaktionen tilbage. Kvittering (efter én ETK_LINJE-linje pr. rettet entry med før og efter):
--   ETK_OK bindinger=<n> tomme=<n> entries=<n> revalideret=<n> sprunget=<n> stale=0 koord_andre=<md5> etiketter_andre=<md5>
--
-- Udvælgelsen: kildens publicerede bindinger med record-etiket, hvis person er offentlig efter publiceringspolitikken
-- (publication_policy.person_publication_allowed: ikke levende, ikke privat, ikke staged). En binding for en ikke-offentlig
-- person springes over og røres ikke (6d-1's præcedens, placement_ceremoni.sql:539-541: revalideringen afviser den, så
-- nye etiketter ville efterlade den stale_published); den tælles som `sprunget` og skal være byte-ens efter (etiketter,
-- seneste hændelse, publiceringsstatus). For de udvalgte gælder 6d-1's revaliderbarhedskriterium (publication_allowed og
-- published_text_sha256) som PRE-gate ETK_PRE_POLITIK; det rammer kun en offentlig person med fx en privat narrativ.
--
-- Filerne indlæses klientside (\set … `cat`), aldrig \copy:
--   sidekort  [{pdf_fra, pdf_til, trykt_fra}, …] (private.sidekort_gyldigt)
--   etiketter [{code, label_foer, label_efter}, …]; en entry nøgles på (kilde, code, label_foer), aldrig på id.
-- Brug: psql -X -At -v ON_ERROR_STOP=1 -v actor=<uuid> -v src=<kilde> -v go=<GO-kode>
--   -v sidekort_path=<fil> -v sidekort_sha=<GO-bundet sha256 af filen>
--   -v etiketter_path=<fil> -v etiketter_sha=<GO-bundet sha256 af filen>
--   -v expect_bindinger=N -v expect_sprunget=N -v expect_tomme=N -v expect_entries=N
--   -v expect_koord_andre=<KOORD_ANDRE fra maal_trin6e2.sql i fase foer>
--   -v expect_etiketter_andre=<ETIKETTER_ANDRE fra fase foer>
--   -v expect_bio_offentlige=N -v expect_fakta_bundne=N   (BIO_OFFENTLIGE/FAKTA_BUNDNE fra fase foer)
--   -f etiket_ceremoni.sql
-- Forventningerne: expect_bindinger = BINDINGER_RECORD, expect_sprunget = SPRUNGET og expect_tomme = UDEN_PLACEMENT
-- (fase ddl);
-- expect_entries = antal rettelser i etiketfilen.
--
-- Den tilladte afvigelse pr. binding (spec §12.2): forrige hændelses after_state og den nye revalideringshændelses
-- after_state er ens, når man ser bort fra labels.record_label, labels.citation_label, binding.record_label,
-- binding.citation_label, provenance.placements[].scheme_entry_label for de rettede entries (og kun fra label_foer til
-- label_efter) samt provenance_sha256, som afledes af dem (og genberegnes her). Efterbetingelserne nævner kun id'er og
-- antal, aldrig tilstandens tekst.
-- Linjeskemaet og sidekortet skrives uden change_set (app.change_set_id er tom hele vejen): før og efter står i
-- kvitteringen, og rækkediffen i generalprøven tillader ingen change_event.
\set QUIET on
\set ON_ERROR_STOP on
\set sk `cat :'sidekort_path'`
\set et `cat :'etiketter_path'`
BEGIN;
SET LOCAL statement_timeout = '15min';
DO $timeout$ BEGIN IF current_setting('statement_timeout')<>'15min' THEN RAISE EXCEPTION 'ETK_PRE_TIMEOUT'; END IF; END $timeout$;
SELECT set_config('request.jwt.claim.sub', :'actor', true), set_config('etk.src', :'src', true),
       set_config('etk.go', :'go', true), set_config('etk.sidekort_sha', :'sidekort_sha', true),
       set_config('etk.etiketter_sha', :'etiketter_sha', true),
       set_config('etk.expect', json_build_object('bindinger', :'expect_bindinger', 'sprunget', :'expect_sprunget',
         'tomme', :'expect_tomme',
         'entries', :'expect_entries', 'koord', :'expect_koord_andre', 'etiketter', :'expect_etiketter_andre',
         'bio', :'expect_bio_offentlige', 'fakta', :'expect_fakta_bundne')::text, true) \g /dev/null
CREATE TEMP TABLE etk_input ON COMMIT DROP AS SELECT :'sk'::text AS sk_text, :'et'::text AS et_text;
-- De rettede entries (fra etiketfilen, slået op på kilde, code og label_foer).
CREATE TEMP TABLE etk_entry (code text PRIMARY KEY, entry_id bigint, label_foer text NOT NULL, label_efter text NOT NULL)
  ON COMMIT DROP;
-- De udvalgte bindinger: kildens publicerede med record-etiket, deres seneste hændelse og de nye etiketter.
CREATE TEMP TABLE etk_binding (binding_id uuid PRIMARY KEY, source_record_id uuid NOT NULL, record_key text NOT NULL,
  person_id bigint NOT NULL, placements integer NOT NULL, foer_event_id uuid, foer_after jsonb,
  ny_record_label text, ny_citation_label text) ON COMMIT DROP;
-- De oversprungne bindinger (ikke-offentlig person) og deres tilstand før; POST kræver dem byte-ens.
CREATE TEMP TABLE etk_sprunget (binding_id uuid PRIMARY KEY, person_id bigint NOT NULL, record_key text NOT NULL,
  record_label text NOT NULL, citation_label text NOT NULL, status text NOT NULL, foer_event_id uuid,
  publication_status text, placements integer NOT NULL) ON COMMIT DROP;

-- Tilstanden uden de tilladte afvigelser (spec §12.2). p_entries = de rettede entries.
CREATE FUNCTION pg_temp.etk_strip(p jsonb, p_entries bigint[]) RETURNS jsonb LANGUAGE sql IMMUTABLE AS $f$
  SELECT jsonb_set(p #- '{labels,record_label}' #- '{labels,citation_label}' #- '{binding,record_label}'
                     #- '{binding,citation_label}' #- '{provenance_sha256}',
                   '{provenance,placements}',
                   coalesce((SELECT jsonb_agg(CASE WHEN (x.e->>'scheme_entry_id')::bigint=ANY(p_entries)
                                                   THEN x.e-'scheme_entry_label' ELSE x.e END ORDER BY x.o)
                               FROM jsonb_array_elements(p #> '{provenance,placements}') WITH ORDINALITY x(e,o)),
                            '[]'::jsonb))
$f$;
-- Seneste publiceringshændelse pr. binding (samme orden som private.narrative_record_state).
CREATE FUNCTION pg_temp.etk_seneste(p_binding uuid) RETURNS private.narrative_publication_event LANGUAGE sql STABLE AS $f$
  SELECT e.* FROM private.narrative_publication_event e WHERE e.binding_id=p_binding
   ORDER BY e.stream_version DESC, e.created_at DESC, e.id DESC LIMIT 1
$f$;
-- Andre kilders koordinater og bindingsetiketter (samme udtryk som maal_trin6e2.sql).
-- Koordinaterne læses som gæst (uden uid) ligesom i maal_trin6e2.sql: siden 2026-11-13 (decisions, POC'ets regel for
-- levende) ser redaktionen også levende, private og staged personers koordinater, og ceremonien kører med redaktørens
-- uid. Uid'en sættes tilbage bagefter (revalideringen kræver den).
CREATE FUNCTION pg_temp.etk_koord_andre(p_src bigint) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE v_uid text:=coalesce(current_setting('request.jwt.claim.sub',true),''); v text;
BEGIN
  PERFORM set_config('request.jwt.claim.sub','',true);
  SELECT md5(coalesce(string_agg(ROW(c.person_id,c.source_id,c.legacy_line_code,c.printed_number,c.printed_number_label,
         c.generation_local,c.generation_global,c.kuld_label,c.provenance_kind)::text,E'\n' ORDER BY c.person_id,c.source_id),''))
    INTO v FROM public.public_person_source_coordinates() c WHERE c.source_id<>p_src;
  PERFORM set_config('request.jwt.claim.sub',v_uid,true);
  RETURN v;
END $f$;
CREATE FUNCTION pg_temp.etk_etiketter_andre(p_src bigint) RETURNS text LANGUAGE sql STABLE AS $f$
  SELECT md5(coalesce(string_agg(concat_ws('|',b.id,b.record_label,b.citation_label),E'\n' ORDER BY b.id),''))
    FROM private.narrative_record_publication b
    JOIN private.source_record sr ON sr.id=b.source_record_id AND sr.source_id<>p_src
$f$;
-- Andre kilders publiceringshændelser (antal; ceremonien må ikke skrive nogen).
SELECT count(*) AS g_andre_events FROM private.narrative_publication_event WHERE source_id<>:src \gset

DO $pre$
DECLARE v_src bigint; e jsonb:=current_setting('etk.expect')::jsonb; i etk_input%ROWTYPE; v_sk jsonb; v_et jsonb;
  v_n bigint; v_id bigint; r record;
BEGIN
  -- Argumenterne.
  IF current_setting('etk.src') !~ '^-?[0-9]{1,18}$' OR btrim(current_setting('etk.go'))=''
     OR current_setting('request.jwt.claim.sub') !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
     OR coalesce(e->>'koord','') !~ '^[0-9a-f]{32}$' OR coalesce(e->>'etiketter','') !~ '^[0-9a-f]{32}$'
     OR EXISTS (SELECT 1 FROM unnest(ARRAY['bindinger','sprunget','tomme','entries','bio','fakta']) k WHERE coalesce(e->>k,'') !~ '^[0-9]{1,9}$')
     OR current_setting('etk.sidekort_sha') !~ '^[0-9a-f]{64}$' OR current_setting('etk.etiketter_sha') !~ '^[0-9a-f]{64}$' THEN
    RAISE EXCEPTION 'ETK_PRE_ARGS';
  END IF;
  v_src:=current_setting('etk.src')::bigint;
  IF public.current_rolle() IS DISTINCT FROM 'redaktion' THEN RAISE EXCEPTION 'ETK_PRE_ROLE'; END IF;
  -- DDL'en fra Task 1-4 (samme markører som maal_trin6e2.sql).
  IF NOT (to_regprocedure('public.source_trykt_side(bigint,text)') IS NOT NULL
          AND to_regprocedure('private.narrative_record_wanted_labels(uuid)') IS NOT NULL
          AND to_regprocedure('private.record_key_uden_bognoegle(text)') IS NOT NULL
          AND EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid='public.source'::regclass AND attname='sidekort' AND NOT attisdropped)
          AND coalesce((SELECT pg_get_constraintdef(oid) LIKE '%record_label = ''''%' FROM pg_constraint
                         WHERE conrelid='private.narrative_record_publication'::regclass
                           AND conname='narrative_record_publication_record_label_check'),false)
          AND coalesce(position('printed_page' IN
                         pg_get_function_result(to_regprocedure('public.public_person_source_coordinates()')))>0,false)) THEN
    RAISE EXCEPTION 'ETK_PRE_DDL';
  END IF;
  IF btrim(coalesce(current_setting('app.change_set_id',true),''))<>'' THEN RAISE EXCEPTION 'ETK_PRE_GUC'; END IF;
  -- Fase: kilden findes og har intet sidekort endnu (genkørsel stopper her).
  PERFORM 1 FROM public.source WHERE id=v_src;
  IF NOT FOUND THEN RAISE EXCEPTION 'ETK_PRE_ARGS'; END IF;
  IF (SELECT sidekort FROM public.source WHERE id=v_src) IS NOT NULL THEN RAISE EXCEPTION 'ETK_PRE_FASE'; END IF;
  -- Filerne er de GO-bundne (psql's `cat` fjerner én afsluttende linjeskift).
  SELECT * INTO i FROM etk_input;
  IF current_setting('etk.sidekort_sha') NOT IN (encode(extensions.digest(i.sk_text,'sha256'),'hex'),
                                                 encode(extensions.digest(i.sk_text||E'\n','sha256'),'hex'))
     OR current_setting('etk.etiketter_sha') NOT IN (encode(extensions.digest(i.et_text,'sha256'),'hex'),
                                                     encode(extensions.digest(i.et_text||E'\n','sha256'),'hex')) THEN
    RAISE EXCEPTION 'ETK_PRE_SHA';
  END IF;
  BEGIN v_sk:=i.sk_text::jsonb; v_et:=i.et_text::jsonb;
  EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'ETK_PRE_FIL'; END;
  IF NOT coalesce(private.sidekort_gyldigt(v_sk),false) THEN RAISE EXCEPTION 'ETK_PRE_SIDEKORT'; END IF;
  -- Etiketfilen: objekter med præcis code/label_foer/label_efter (ikke-tomme strenge, før ≠ efter), unikke koder.
  IF jsonb_typeof(v_et)<>'array' OR jsonb_array_length(v_et)<>(e->>'entries')::int
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(v_et) x
                 WHERE jsonb_typeof(x)<>'object'
                    OR (SELECT array_agg(k ORDER BY k) FROM jsonb_object_keys(x) k)
                         IS DISTINCT FROM ARRAY['code','label_efter','label_foer']
                    OR jsonb_typeof(x->'code')<>'string' OR jsonb_typeof(x->'label_foer')<>'string'
                    OR jsonb_typeof(x->'label_efter')<>'string'
                    OR btrim(x->>'code')='' OR btrim(x->>'label_foer')='' OR btrim(x->>'label_efter')=''
                    OR x->>'label_foer'=x->>'label_efter')
     OR (SELECT count(DISTINCT x->>'code') FROM jsonb_array_elements(v_et) x)<>jsonb_array_length(v_et) THEN
    RAISE EXCEPTION 'ETK_PRE_FIL';
  END IF;
  -- Hver label_foer findes præcis én gang for (kilde, code).
  INSERT INTO etk_entry(code,label_foer,label_efter)
  SELECT x->>'code', x->>'label_foer', x->>'label_efter' FROM jsonb_array_elements(v_et) x;
  FOR r IN SELECT * FROM etk_entry LOOP
    SELECT count(*), min(le.id) INTO v_n, v_id
      FROM public.lineage_scheme s JOIN public.lineage_scheme_entry le ON le.scheme_id=s.id
     WHERE s.source_id=v_src AND le.code=r.code AND le.label=r.label_foer;
    IF v_n<>1 THEN RAISE EXCEPTION 'ETK_PRE_ETIKET n=%', v_n; END IF;
    UPDATE etk_entry SET entry_id=v_id WHERE code=r.code;
  END LOOP;
  -- Kandidaterne (kildens publicerede med record-etiket), deres seneste hændelse og tilstand; delt efter personens
  -- offentlighed i publiceringspolitikken.
  CREATE TEMP TABLE etk_kandidat ON COMMIT DROP AS
  SELECT b.id AS binding_id, b.source_record_id, sr.record_key, n.subjekt_id AS person_id, b.record_label,
         b.citation_label, b.status,
         (SELECT count(*) FROM private.source_record_placement_current pc
           WHERE pc.source_record_id=b.source_record_id AND pc.decision_status='accepted')::integer AS placements,
         l.id AS foer_event_id, l.after_state AS foer_after,
         private.narrative_record_state(n.subjekt_id, v_src, sr.record_key) AS s
    FROM private.narrative_record_publication b
    JOIN private.source_record sr ON sr.id=b.source_record_id AND sr.source_id=v_src
    JOIN public.narrative n ON n.id=b.narrative_id AND n.subjekt_type='person'
    LEFT JOIN LATERAL pg_temp.etk_seneste(b.id) l ON true
   WHERE b.status='published' AND b.record_label ~ '^record-';
  INSERT INTO etk_binding(binding_id,source_record_id,record_key,person_id,placements,foer_event_id,foer_after)
  SELECT binding_id, source_record_id, record_key, person_id, placements, foer_event_id, foer_after FROM etk_kandidat
   WHERE coalesce((s #>> '{publication_state,publication_policy,person_publication_allowed}')::boolean,false);
  INSERT INTO etk_sprunget
  SELECT binding_id, person_id, record_key, record_label, citation_label, status, foer_event_id,
         s->>'publication_status', placements FROM etk_kandidat
   WHERE NOT coalesce((s #>> '{publication_state,publication_policy,person_publication_allowed}')::boolean,false);
  IF (SELECT count(*) FROM etk_binding)<>(e->>'bindinger')::bigint
     OR (SELECT count(*) FROM etk_sprunget)<>(e->>'sprunget')::bigint THEN
    RAISE EXCEPTION 'ETK_PRE_BINDINGER n=% sprunget=%', (SELECT count(*) FROM etk_binding),
      (SELECT count(*) FROM etk_sprunget);
  END IF;
  -- Opdelingen som helhed: kildens publicerede bindinger, hvis seneste hændelse bærer en record-etiket (uden narrativ-
  -- join), er præcis de udvalgte og de oversprungne.
  SELECT count(*) INTO v_n
    FROM private.narrative_record_publication b
    JOIN private.source_record sr ON sr.id=b.source_record_id AND sr.source_id=v_src
    LEFT JOIN LATERAL pg_temp.etk_seneste(b.id) l ON true
   WHERE b.status='published' AND l.after_state #>> '{binding,record_label}' ~ '^record-';
  IF v_n<>(e->>'bindinger')::bigint+(e->>'sprunget')::bigint THEN
    RAISE EXCEPTION 'ETK_PRE_OPDELING n=%', v_n;
  END IF;
  -- En oversprunget binding må ikke blive forældet af ceremonien (dens post må ikke ligge i en rettet entry).
  IF EXISTS (SELECT 1 FROM etk_sprunget x JOIN private.source_record_placement_current pc
                 ON pc.source_record_id=(SELECT source_record_id FROM etk_kandidat k WHERE k.binding_id=x.binding_id)
                AND pc.decision_status='accepted'
               JOIN etk_entry t ON t.entry_id=pc.scheme_entry_id) THEN
    RAISE EXCEPTION 'ETK_PRE_SPRUNGET';
  END IF;
  -- Kun publicerede bindinger bærer record-etiketten (en kladde eller tilbagetrukken ville beholde den).
  IF EXISTS (SELECT 1 FROM private.narrative_record_publication b
               JOIN private.source_record sr ON sr.id=b.source_record_id AND sr.source_id=v_src
              WHERE b.status<>'published' AND b.record_label ~ '^record-') THEN
    RAISE EXCEPTION 'ETK_PRE_STATUS';
  END IF;
  -- 0 stale_published for kilden, og hver udvalgt bindings seneste hændelse bærer bindingens etiketter.
  IF EXISTS (SELECT 1 FROM private.narrative_record_publication b
               JOIN private.source_record sr ON sr.id=b.source_record_id AND sr.source_id=v_src
               JOIN public.narrative n ON n.id=b.narrative_id AND n.subjekt_type='person',
                    LATERAL private.narrative_record_state(n.subjekt_id, sr.source_id, sr.record_key) s
              WHERE s->>'publication_status'='stale_published') THEN
    RAISE EXCEPTION 'ETK_PRE_STALE';
  END IF;
  IF EXISTS (SELECT 1 FROM etk_binding x JOIN private.narrative_record_publication b ON b.id=x.binding_id
              WHERE x.foer_event_id IS NULL
                 OR x.foer_after #>> '{binding,record_label}' IS DISTINCT FROM b.record_label
                 OR x.foer_after #>> '{labels,record_label}' IS DISTINCT FROM b.record_label
                 OR x.foer_after #>> '{binding,citation_label}' IS DISTINCT FROM b.citation_label
                 OR x.foer_after #>> '{labels,citation_label}' IS DISTINCT FROM b.citation_label) THEN
    RAISE EXCEPTION 'ETK_PRE_STALE';
  END IF;
  -- Hver udvalgt binding (offentlig person) kan revalideres: 6d-1's kriterium (placement_ceremoni.sql:549-552). En
  -- privat narrativ for en offentlig person ville ellers kaste midt i revalideringen.
  SELECT count(*) INTO v_n FROM etk_binding x JOIN etk_kandidat k USING (binding_id)
   WHERE NOT coalesce((k.s#>>'{publication_state,publication_policy,publication_allowed}')::boolean,false)
      OR k.s->>'published_text_sha256' IS NULL;
  IF v_n<>0 THEN RAISE EXCEPTION 'ETK_PRE_POLITIK n=%', v_n; END IF;
  -- Ingen udvalgt post med flere accepterede placements (etiketreglen kaster ellers midt i skrivningen).
  IF EXISTS (SELECT 1 FROM etk_binding WHERE placements>1) THEN RAISE EXCEPTION 'ETK_PRE_TVETYDIG'; END IF;
END $pre$;

-- Skrivning 1: kildens sidekort.
UPDATE public.source SET sidekort=(SELECT sk_text::jsonb FROM etk_input) WHERE id=:src AND sidekort IS NULL;
-- Skrivning 2: linjeskemaets etiketter (nøglet på entry fra PRE, kun hvis etiketten stadig er label_foer).
UPDATE public.lineage_scheme_entry le SET label=x.label_efter FROM etk_entry x
 WHERE le.id=x.entry_id AND le.label=x.label_foer;
-- Skrivning 3: bindingernes etiketter fra etiketreglen (efter sidekort og linjenavne, som reglen læser).
UPDATE etk_binding x SET ny_record_label=w->>'record_label', ny_citation_label=w->>'citation_label'
  FROM (SELECT binding_id, private.narrative_record_wanted_labels(source_record_id) AS w FROM etk_binding) y
 WHERE y.binding_id=x.binding_id;
UPDATE private.narrative_record_publication b SET record_label=x.ny_record_label, citation_label=x.ny_citation_label
  FROM etk_binding x WHERE b.id=x.binding_id AND b.status='published';
DO $mid$
DECLARE v_src bigint:=current_setting('etk.src')::bigint; e jsonb:=current_setting('etk.expect')::jsonb;
BEGIN
  IF btrim(coalesce(current_setting('app.change_set_id',true),''))<>'' THEN RAISE EXCEPTION 'ETK_MID_GUC'; END IF;
  IF (SELECT sidekort FROM public.source WHERE id=v_src) IS DISTINCT FROM (SELECT sk_text::jsonb FROM etk_input) THEN
    RAISE EXCEPTION 'ETK_MID_SIDEKORT';
  END IF;
  IF (SELECT count(*) FROM etk_entry x JOIN public.lineage_scheme_entry le ON le.id=x.entry_id AND le.label=x.label_efter)
       <>(e->>'entries')::bigint THEN
    RAISE EXCEPTION 'ETK_MID_ETIKETTER';
  END IF;
  IF EXISTS (SELECT 1 FROM etk_binding x LEFT JOIN private.narrative_record_publication b ON b.id=x.binding_id
              WHERE x.ny_record_label IS NULL OR x.ny_citation_label IS NULL OR x.ny_record_label ~ '^record-'
                 OR b.record_label IS DISTINCT FROM x.ny_record_label OR b.citation_label IS DISTINCT FROM x.ny_citation_label) THEN
    RAISE EXCEPTION 'ETK_MID_BINDINGER';
  END IF;
END $mid$;
ANALYZE public.source, public.lineage_scheme_entry, private.narrative_record_publication;

-- Skrivning 4: revalidering. Én klientdrevet sætning pr. forældet udvalgt publicering, slået op via recorden (en anden
-- forældet binding i kilden revalideres ikke; POST_SPRUNGET/POST_STALE stopper så);
-- app.change_set_id ryddes før hvert kald. Tilstands-sha'en læses som ejer, sætningerne køres som redaktør.
CREATE TEMP TABLE etk_reval ON COMMIT DROP AS
SELECT row_number() OVER (ORDER BY sr.record_key COLLATE "C", b.id) AS ord, b.id AS binding_id,
       format('SELECT set_config(%L,%L,true), public.red_revalider_person_narrative_record(%s,%s,%L,%L)',
              'app.change_set_id', '', n.subjekt_id, :src, sr.record_key, s->>'state_sha256') AS stmt
  FROM private.narrative_record_publication b
  JOIN etk_binding x ON x.binding_id=b.id
  JOIN private.source_record sr ON sr.id=b.source_record_id AND sr.source_id=:src
  JOIN public.narrative n ON n.id=b.narrative_id AND n.subjekt_type='person',
       LATERAL private.narrative_record_state(n.subjekt_id, sr.source_id, sr.record_key) s
 WHERE s->>'publication_status'='stale_published';
GRANT SELECT ON etk_reval TO authenticated;
SELECT count(*) AS g_reval FROM etk_reval \gset
SET LOCAL ROLE authenticated;
\o /dev/null
SELECT stmt FROM etk_reval ORDER BY ord \gexec
\o
RESET ROLE;
ANALYZE private.narrative_publication_event, private.narrative_record_publication, public.change_set;
SELECT set_config('app.change_set_id','',true), set_config('etk.reval', :'g_reval', true),
       set_config('etk.andre_events', :'g_andre_events', true) \g /dev/null
-- Læserne som anon (person- og familielisten beregnes som ejer; samme udtryk som maal_trin6e2.sql), uden uid (gæst, som
-- målingen; redaktørens uid sættes tilbage bagefter).
SELECT '{'||coalesce((SELECT string_agg(id::text,',' ORDER BY id) FROM public.person WHERE public.person_offentlig(id)),'')||'}' AS ids \gset
SELECT set_config('request.jwt.claim.sub','',true) \g /dev/null
SET LOCAL ROLE anon;
SELECT count(*) AS bio_offentlige FROM public.public_person_bio_source_versions_v2(:'ids'::bigint[]) \gset
SELECT count(*) AS fakta_bundne FROM public.public_person_facts(:'ids'::bigint[]) WHERE record_ref IS NOT NULL \gset
RESET ROLE;
SELECT set_config('request.jwt.claim.sub', :'actor', true) \g /dev/null
SELECT set_config('etk.bio', :'bio_offentlige', true), set_config('etk.fakta', :'fakta_bundne', true) \g /dev/null

DO $post$
DECLARE v_src bigint:=current_setting('etk.src')::bigint; e jsonb:=current_setting('etk.expect')::jsonb;
  v_entries bigint[]:=ARRAY(SELECT entry_id FROM etk_entry); v_lbl text; v_n bigint;
BEGIN
  IF btrim(coalesce(current_setting('app.change_set_id',true),''))<>'' THEN RAISE EXCEPTION 'ETK_POST_GUC'; END IF;
  -- Revalideret = præcis de udvalgte bindinger (som mængde, ikke kun antal).
  IF current_setting('etk.reval')::bigint<>(e->>'bindinger')::bigint
     OR EXISTS ((SELECT binding_id FROM etk_reval) EXCEPT (SELECT binding_id FROM etk_binding))
     OR EXISTS ((SELECT binding_id FROM etk_binding) EXCEPT (SELECT binding_id FROM etk_reval)) THEN
    RAISE EXCEPTION 'ETK_POST_REVALIDERET n=%', current_setting('etk.reval');
  END IF;
  -- De oversprungne er byte-ens med før: etiketter, status, seneste hændelse og publiceringsstatus.
  SELECT count(*) INTO v_n
    FROM etk_sprunget x LEFT JOIN private.narrative_record_publication b ON b.id=x.binding_id
    LEFT JOIN LATERAL pg_temp.etk_seneste(x.binding_id) l ON true
   WHERE b.id IS NULL OR b.record_label IS DISTINCT FROM x.record_label
      OR b.citation_label IS DISTINCT FROM x.citation_label OR b.status IS DISTINCT FROM x.status
      OR l.id IS DISTINCT FROM x.foer_event_id
      OR (private.narrative_record_state(x.person_id, v_src, x.record_key)->>'publication_status')
           IS DISTINCT FROM x.publication_status;
  IF v_n<>0 OR (SELECT count(*) FROM etk_sprunget)<>(e->>'sprunget')::bigint THEN
    RAISE EXCEPTION 'ETK_POST_SPRUNGET n=%', v_n;
  END IF;
  -- 0 stale_published i kilden.
  IF EXISTS (SELECT 1 FROM private.narrative_record_publication b
               JOIN private.source_record sr ON sr.id=b.source_record_id AND sr.source_id=v_src
               JOIN public.narrative n ON n.id=b.narrative_id AND n.subjekt_type='person',
                    LATERAL private.narrative_record_state(n.subjekt_id, sr.source_id, sr.record_key) s
              WHERE s->>'publication_status'='stale_published') THEN
    RAISE EXCEPTION 'ETK_POST_STALE';
  END IF;
  -- Ingen udvalgt bindings seneste hændelse bærer en record-etiket.
  IF EXISTS (SELECT 1 FROM etk_binding b
               LEFT JOIN LATERAL pg_temp.etk_seneste(b.binding_id) l ON true
              WHERE l.after_state #>> '{labels,record_label}' ~ '^record-'
                 OR l.after_state #>> '{binding,record_label}' ~ '^record-') THEN
    RAISE EXCEPTION 'ETK_POST_RECORD';
  END IF;
  -- Tomme postdele: præcis de udvalgte uden placement, med citation_label '<udgave>, s. N'.
  SELECT coalesce(s.udgave,s.titel) INTO v_lbl FROM public.source s WHERE s.id=v_src;
  IF (SELECT count(*) FROM etk_binding WHERE ny_record_label='')<>(e->>'tomme')::bigint
     OR EXISTS (SELECT 1 FROM etk_binding WHERE (ny_record_label='')<>(placements=0))
     OR EXISTS (SELECT 1 FROM etk_binding WHERE placements=0
                   AND (NOT starts_with(ny_citation_label,v_lbl||', s. ')
                        OR substr(ny_citation_label,length(v_lbl||', s. ')+1) !~ '^[0-9]+(-[0-9]+)?(, [0-9]+(-[0-9]+)?)*$')) THEN
    RAISE EXCEPTION 'ETK_POST_TOMME n=%', (SELECT count(*) FROM etk_binding WHERE ny_record_label='');
  END IF;
  -- Afstemning pr. binding: én ny revalidated-hændelse; dens after_state = den forrige uden de tilladte afvigelser;
  -- de nye etiketter står i både labels og binding; provenance_sha256 passer til proveniensen; en rettet entry går
  -- fra label_foer til label_efter, og ingen anden entry-etiket ændres.
  SELECT count(*) INTO v_n
    FROM etk_binding x LEFT JOIN LATERAL pg_temp.etk_seneste(x.binding_id) l ON true
   WHERE l.id IS NULL OR l.id=x.foer_event_id OR l.event_type<>'revalidated'
      OR pg_temp.etk_strip(l.after_state,v_entries) IS DISTINCT FROM pg_temp.etk_strip(x.foer_after,v_entries)
      OR l.after_state #>> '{labels,record_label}' IS DISTINCT FROM x.ny_record_label
      OR l.after_state #>> '{binding,record_label}' IS DISTINCT FROM x.ny_record_label
      OR l.after_state #>> '{labels,citation_label}' IS DISTINCT FROM x.ny_citation_label
      OR l.after_state #>> '{binding,citation_label}' IS DISTINCT FROM x.ny_citation_label
      OR l.after_state->>'provenance_sha256' IS DISTINCT FROM
           encode(extensions.digest((l.after_state->'provenance')::text,'sha256'),'hex')
      OR EXISTS (SELECT 1 FROM jsonb_array_elements(x.foer_after #> '{provenance,placements}') p
                   JOIN etk_entry t ON t.entry_id=(p->>'scheme_entry_id')::bigint
                  WHERE p->>'scheme_entry_label' IS DISTINCT FROM t.label_foer)
      OR EXISTS (SELECT 1 FROM jsonb_array_elements(l.after_state #> '{provenance,placements}') p
                   JOIN etk_entry t ON t.entry_id=(p->>'scheme_entry_id')::bigint
                  WHERE p->>'scheme_entry_label' IS DISTINCT FROM t.label_efter);
  IF v_n<>0 THEN RAISE EXCEPTION 'ETK_POST_AFSTEMNING n=%', v_n; END IF;
  -- Bindingernes etiketter er etiketreglens (genberegnet efter revalideringen).
  IF EXISTS (SELECT 1 FROM etk_binding x JOIN private.narrative_record_publication b ON b.id=x.binding_id
              WHERE b.status<>'published'
                 OR jsonb_build_object('record_label',b.record_label,'citation_label',b.citation_label)
                      IS DISTINCT FROM private.narrative_record_wanted_labels(b.source_record_id)) THEN
    RAISE EXCEPTION 'ETK_POST_ETIKETREGEL';
  END IF;
  IF private.placement_header_violations(v_src)<>0 THEN RAISE EXCEPTION 'ETK_POST_NEAREST'; END IF;
  -- Andre kilder: koordinater og bindingsetiketter = fase foer, og ingen nye publiceringshændelser.
  IF pg_temp.etk_koord_andre(v_src) IS DISTINCT FROM e->>'koord' THEN RAISE EXCEPTION 'ETK_POST_ANDRE koord'; END IF;
  IF pg_temp.etk_etiketter_andre(v_src) IS DISTINCT FROM e->>'etiketter' THEN
    RAISE EXCEPTION 'ETK_POST_ANDRE etiketter';
  END IF;
  IF (SELECT count(*) FROM private.narrative_publication_event WHERE source_id<>v_src)
       <>current_setting('etk.andre_events')::bigint THEN
    RAISE EXCEPTION 'ETK_POST_ANDRE haendelser';
  END IF;
  -- Læserne: offentlige biografier og bundne fakta (som anon) = fase foer.
  IF current_setting('etk.bio')::bigint<>(e->>'bio')::bigint THEN
    RAISE EXCEPTION 'ETK_POST_LAESER bio=%', current_setting('etk.bio');
  END IF;
  IF current_setting('etk.fakta')::bigint<>(e->>'fakta')::bigint THEN
    RAISE EXCEPTION 'ETK_POST_LAESER fakta=%', current_setting('etk.fakta');
  END IF;
END $post$;
-- Kvitteringens stale-tal tælles i transaktionen (efter ETK_POST_STALE, inden for de 15 min).
SELECT count(*) FILTER (WHERE s->>'publication_status'='stale_published') AS g_stale
  FROM private.narrative_record_publication b
  JOIN private.source_record sr ON sr.id=b.source_record_id AND sr.source_id=:src
  JOIN public.narrative n ON n.id=b.narrative_id AND n.subjekt_type='person',
       LATERAL private.narrative_record_state(n.subjekt_id, sr.source_id, sr.record_key) s \gset
SELECT count(*) AS g_bindinger, count(*) FILTER (WHERE ny_record_label='') AS g_tomme FROM etk_binding \gset
SELECT count(*) AS g_sprunget FROM etk_sprunget \gset
SELECT count(*) AS g_entries,
       string_agg(format('ETK_LINJE code=%s foer=%s efter=%s', code, label_foer, label_efter), E'\n' ORDER BY code COLLATE "C")
         AS g_linjer FROM etk_entry \gset
SELECT pg_temp.etk_koord_andre(:src) AS g_koord, pg_temp.etk_etiketter_andre(:src) AS g_etiketter \gset
COMMIT;
\echo :g_linjer
\echo ETK_OK bindinger=:g_bindinger tomme=:g_tomme entries=:g_entries revalideret=:g_reval sprunget=:g_sprunget stale=:g_stale koord_andre=:g_koord etiketter_andre=:g_etiketter
