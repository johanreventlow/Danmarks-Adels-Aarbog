-- record_persona (persona for en helpost uden tekst): dataceremonien for de poster, projektejeren har godkendt på et
-- kortark. I ÉN transaktion og i denne rækkefølge, pr. manifestlinje (én helpost uden tekst):
--   1. PRE (intet skrevet): argumenter, rolle, DDL, profil, fase, filernes sha, manifestets form, svarfilen (præcis ét J
--      pr. kort og del; ethvert N stopper), og under lås: førtilstanden mod manifestet.
--   2. authorize → begin → apply (ét record_persona-element pr. linje) → finalize, som redaktøren.
--   3. LOCK TABLE public.change_set IN ACCESS EXCLUSIVE MODE (før første identitet; låseorden nedenfor).
--   4. identiteter: red_afgoer_source_persona(persona, 0, 'same', linjens person, …, human_sheet-kontekst).
--   5. placements: private.write_record_placement (kortets værdier, intet trykt nummer) og write_persona_placement
--      (principal_member på helpost-observationen); placement_header_violations(kilde) skal være 0.
--   6. ledger: private.record_legacy_disposition(person, kilde, 'mapped', placement) → én ny version pr. person.
--   7. medlemskab: forhåndsvisningens eligible-mængde skal være præcis manifestets personer (ellers
--      T_RP_PRE_MEDLEMSKAB og alt rulles tilbage); promovering med forhåndsvisningens sha.
--   8. narrative_publication_state = accepted_identity (eligible) for hver post.
--   9. kladder sidst: red_upsert_person_narrative_record(person, kilde, post, tekst, false = ikke privat, tilstands-sha);
--      tekst = btrim((private.relation_fold_raw_text(helpostens forekomst.verbatim_text)).folded), og dens sha skal være
--      manifestets foldet_sha256. app.change_set_id nulstilles før og efter hvert redaktør-kald.
--  10. POST og kvittering: change_set 'record_persona_ceremoni' med kilden som subjekt og summary
--      `T_RP_OK personas=<n> identiteter=<n> placements=<n> medlemskab=<n> kladder=<n>`; ceremonien udskriver samme linje.
-- Kildeparametriseret og editionsneutral: ingen kilde, udgave, post, person eller profil i logikken; persona-nøglens
-- prefix og helpost-slagsen kommer fra writer-profilen (-v profile_id), alt andet fra manifestet og -v.
--
-- Fejlkoder (alle ruller hele transaktionen tilbage; PRE_* stopper før authorize):
--   T_RP_PRE_ARGS/TIMEOUT/ROLE/DDL/GUC/ISOLATION  argumenter, 15 min-grænse, redaktionsrolle (via -v actor), DDL'en
--                 (operationen og spærringen af legacy-fortrydelsen) og kontrakt v2, ingen aktiv change_set, READ COMMITTED
--   T_RP_PRE_PROFIL   profilrækken findes ikke, har en anden sha end den GO-bundne, eller mangler persona_key_prefix
--   T_RP_PRE_FASE     allerede kørt: en reimport-batch for manifestets sha findes i kilden, eller en post har en persona
--   T_RP_PRE_SHA      manifestets eller svarfilens indhold har ikke den GO-bundne sha
--   T_RP_PRE_SVAR     svarfilen: første linje bærer ikke manifestets sha, et svar er N, mangler, er dobbelt, ukendt
--                     eller har forkert form
--   T_RP_PRE_MANIFEST manifestets form, eller en førtilstand afviger (efterprøvet under lås): posten findes, helposten og
--                     dens ene mention (id og tekst-sha), ingen binding og ingen placement på posten, den foldede teksts
--                     sha, personen (afdød, én person_external_id i kilden), aliaset (samme_som), legacy-narrativen
--                     (personens eneste i kilden, status `withdrawn`), linjeskemaets entry, overskrifterne (art, kørsel,
--                     rendition) og human_header_levels
--   T_RP_PRE_MEDLEMSKAB  forhåndsvisningens eligible-mængde er ikke præcis manifestets personer
--   T_RP_WRITE_*      en skrivning gav ikke det forventede (batch, identitet, placement, overskrifter, ledger, medlemskab,
--                     narrativtilstand, kladde)
--   T_RP_POST_*       efterbetingelser: tilstand, rækker, overskrifter, FAKTA, BIO, KOORD_2018_20, synlige tekster
-- Låseorden (som writerne): kontraktlåsen (delt) → writer-låsen (kilde, profil) → kildens kandidatlås (delt) → posterne
-- (FOR UPDATE, id-orden) → deres publikationsrækker → [authorize/apply/finalize] → change_set (ACCESS EXCLUSIVE) →
-- personaer/identiteter → personer. En resterende låsecyklus ender i 40P01 og fuld rollback.
--
-- Filerne indlæses klientside (\set … `cat`), aldrig \copy; psql's backtick fjerner én afsluttende linjeskift, så de
-- bundne sha'er accepteres både med og uden den (som placement_ceremoni.sql). Runneren giver de GO-bundne sha'er.
--   manifest  JSONL, én kanonisk linje (sorterede nøgler) pr. kort med netop nøglerne alias_person_id (person|null),
--             foldet_sha256, helpost_observation_id, kort (K<n>), legacy_narrative_id (id|null), legacy_status_foer,
--             linje (1..), mention_id, mention_text_sha256, person_id, placement{generation_label_raw,
--             generation_local, header_ids{niveau: observation}, human_header_levels[], kuld_label, scheme_entry_id,
--             section_path[]}, record_key. Hashes: sha256 hex over UTF-8.
--   svar      ren tekst: første linje er en kommentar med `manifest_sha256=<manifestets sha>`; ellers `#`-kommentarer og
--             én linje pr. kort og del: `K<n>-identitet J` og `K<n>-placement J`, evt. efterfulgt af `# …`.
-- Sha'erne: sheet_sha256 = manifestets sha (kortarkets maskinform; personaens payload, identitetens og placementens
--   evidens), rows_sha256 = svarfilens sha (identitetens og placementens evidens); line = manifestlinjens `linje`.
--   Autorisationens manifest_sha256 = manifestets sha og preview_sha256 = svarfilens sha (batchens nøgle; fasen).
-- Brug: psql -X -At -v ON_ERROR_STOP=1 -v actor=<redaktørens uuid> -v src=<kilde> -v profile_id=<writer-profil>
--   -v profile_sha=<profilens GO-bundne sha256> -v header_rule_version=<overskrifternes kørsel (run_key)>
--   -v manifest_path=<fil> -v manifest_sha=<GO-bundet sha256> -v svar_path=<fil> -v svar_sha=<GO-bundet sha256>
--   -f record_persona_ceremoni.sql
-- Filerne kan nævne poster; runneren sender stdout og stderr til en privat fil.
\set QUIET on
\set ON_ERROR_STOP on
\if :{?actor}
\else
DO $$ BEGIN RAISE EXCEPTION 'T_RP_PRE_ARGS: -v actor mangler'; END $$;
\endif
\if :{?src}
\else
DO $$ BEGIN RAISE EXCEPTION 'T_RP_PRE_ARGS: -v src mangler'; END $$;
\endif
\if :{?profile_id}
\else
DO $$ BEGIN RAISE EXCEPTION 'T_RP_PRE_ARGS: -v profile_id mangler'; END $$;
\endif
\if :{?profile_sha}
\else
DO $$ BEGIN RAISE EXCEPTION 'T_RP_PRE_ARGS: -v profile_sha mangler'; END $$;
\endif
\if :{?header_rule_version}
\else
DO $$ BEGIN RAISE EXCEPTION 'T_RP_PRE_ARGS: -v header_rule_version mangler'; END $$;
\endif
\if :{?manifest_path}
\else
DO $$ BEGIN RAISE EXCEPTION 'T_RP_PRE_ARGS: -v manifest_path mangler'; END $$;
\endif
\if :{?manifest_sha}
\else
DO $$ BEGIN RAISE EXCEPTION 'T_RP_PRE_ARGS: -v manifest_sha mangler'; END $$;
\endif
\if :{?svar_path}
\else
DO $$ BEGIN RAISE EXCEPTION 'T_RP_PRE_ARGS: -v svar_path mangler'; END $$;
\endif
\if :{?svar_sha}
\else
DO $$ BEGIN RAISE EXCEPTION 'T_RP_PRE_ARGS: -v svar_sha mangler'; END $$;
\endif
\set m `cat -- :'manifest_path'`
\set sv `cat -- :'svar_path'`
BEGIN;
SET LOCAL statement_timeout = '15min';
DO $timeout$ BEGIN IF current_setting('statement_timeout')<>'15min' THEN RAISE EXCEPTION 'T_RP_PRE_TIMEOUT'; END IF; END $timeout$;
SELECT set_config('request.jwt.claim.sub', :'actor', true), set_config('rp.src', :'src', true),
       set_config('rp.profile_id', :'profile_id', true), set_config('rp.profile_sha', :'profile_sha', true),
       set_config('rp.rule', :'header_rule_version', true), set_config('rp.manifest_sha', :'manifest_sha', true),
       set_config('rp.svar_sha', :'svar_sha', true), set_config('rp.navn', 'record_persona_ceremoni', true) \g /dev/null
CREATE TEMP TABLE rp_input ON COMMIT DROP AS SELECT :'m'::text AS m_text, :'sv'::text AS sv_text;
-- Én række pr. manifestlinje: linjen, opslagene (post, helpost, mention, forekomstens foldede tekst) og det skrevne.
CREATE TEMP TABLE rp_post (ord integer PRIMARY KEY, kort text NOT NULL UNIQUE, linje integer NOT NULL UNIQUE,
  record_key text NOT NULL UNIQUE, person_id bigint NOT NULL UNIQUE, mention_id uuid NOT NULL UNIQUE, k jsonb NOT NULL,
  record_id uuid, helpost uuid, tekst text, payload jsonb, persona uuid, rp uuid, pp uuid, ledger_foer integer)
  ON COMMIT DROP;
CREATE TEMP TABLE rp_svar (kort text NOT NULL, del text NOT NULL, svar text NOT NULL, PRIMARY KEY (kort,del)) ON COMMIT DROP;
-- Læsernes hashes før skrivningen (sammenlignes i POST).
CREATE TEMP TABLE rp_hash (navn text PRIMARY KEY, foer text NOT NULL) ON COMMIT DROP;

CREATE FUNCTION pg_temp.rp_sha(p_text text) RETURNS text LANGUAGE sql IMMUTABLE AS
  $f$ SELECT encode(sha256(convert_to(p_text,'UTF8')),'hex') $f$;

-- Koordinat-hash (samme udtryk som maal_record_persona.sql): p_andre = rækkerne med source_id <> kilden, ellers kildens.
CREATE FUNCTION pg_temp.rp_koord(p_src bigint,p_andre boolean) RETURNS text LANGUAGE sql AS $f$
  SELECT md5(coalesce(string_agg(concat_ws('|',quote_nullable(c.person_id),quote_nullable(c.source_id),
           quote_nullable(c.legacy_line_code),quote_nullable(c.printed_number),quote_nullable(c.printed_number_label),
           quote_nullable(c.generation_local),quote_nullable(c.generation_global),quote_nullable(c.kuld_label),
           quote_nullable(c.provenance_kind)),E'\n' ORDER BY c.person_id,c.source_id),''))
    FROM public.public_person_source_coordinates() c
   WHERE (c.source_id<>p_src)=p_andre;
$f$;

-- FAKTA, BIO og synlige tekster (samme udtryk som maal_record_persona.sql), beregnet som ægte anon for alle offentlige
-- personer: 'fakta' | 'bio' | 'synlige' (kildens tekster i biografilæseren). Læserne afgør redaktørvisningen ud fra
-- current_rolle(), som læser request.jwt.claim.sub (memory redaktoer-uid-arves-i-tests), så kravet ryddes under
-- læsningen og sættes tilbage til aktøren bagefter; en fejl undervejs ruller hele transaktionen tilbage, så der er
-- ingen tilstand at gendanne i en undtagelsesgren. Målingen kører uden aktør og ser altså det samme.
CREATE FUNCTION pg_temp.rp_laeser(p_hvad text,p_src bigint) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE v_ids bigint[]; v_fids bigint[]; v text; v_sub text:=current_setting('request.jwt.claim.sub',true);
BEGIN
  v_ids:=ARRAY(SELECT id FROM public.person WHERE public.person_offentlig(id) ORDER BY id);
  v_fids:=ARRAY(SELECT id FROM public.family ORDER BY id);
  PERFORM set_config('request.jwt.claim.sub','',true);
  SET LOCAL ROLE anon;
  IF p_hvad='fakta' THEN
    v:=(SELECT md5(coalesce(string_agg(x,E'\n' ORDER BY x COLLATE "C"),''))
          FROM (SELECT 'f|'||f::text AS x FROM public.public_person_facts(v_ids) f
                UNION ALL
                SELECT 's|'||s::text FROM public.public_family_sources(v_fids) s) z);
  ELSIF p_hvad='bio' THEN
    v:=(SELECT md5(coalesce(string_agg(b::text,E'\n' ORDER BY b::text COLLATE "C"),'')) AS bio
          FROM public.public_person_bio_source_versions_v2(v_ids) b);
  ELSE
    v:=(SELECT count(*) FROM public.public_person_bio_source_versions_v2(v_ids) b WHERE b.source_id=p_src)::text;
  END IF;
  RESET ROLE;
  PERFORM set_config('request.jwt.claim.sub',coalesce(v_sub,''),true);
  IF public.current_rolle() IS DISTINCT FROM 'redaktion' THEN RAISE EXCEPTION 'T_RP_PRE_ROLE efter læserkontrol'; END IF;
  RETURN v;
END $f$;

-- Førtilstanden for én manifestlinje (under lås): NULL = i orden, ellers årsagen (uden id'er og tekst).
CREATE FUNCTION pg_temp.rp_tjek(p rp_post,p_kind text) RETURNS text LANGUAGE plpgsql AS $f$
DECLARE v_src bigint:=current_setting('rp.src')::bigint; v_rule text:=current_setting('rp.rule'); k jsonb:=p.k;
  pl jsonb:=p.k->'placement'; v_obs uuid; v_occ record; v_n bigint; v_mid uuid; v_mtext text; v_lvl text; v_hid text;
  v_ok boolean; v_alias bigint;
BEGIN
  IF p.record_id IS NULL THEN RETURN 'post'; END IF;
  BEGIN v_obs:=private.record_helpost_observation(p.record_id,p_kind);
  EXCEPTION WHEN OTHERS THEN RETURN 'helpost'; END;
  IF v_obs IS DISTINCT FROM (k->>'helpost_observation_id')::uuid THEN RETURN 'helpost'; END IF;
  SELECT count(*),min(id::text)::uuid,min(verbatim_text) INTO v_n,v_mid,v_mtext FROM private.source_mention WHERE observation_id=v_obs;
  IF v_n<>1 OR v_mid<>p.mention_id OR pg_temp.rp_sha(v_mtext) IS DISTINCT FROM k->>'mention_text_sha256' THEN RETURN 'mention'; END IF;
  -- Ingen binding (i nogen status) og ingen placement på posten: en post uden tekst og uden placement.
  IF EXISTS (SELECT 1 FROM private.narrative_record_publication WHERE source_record_id=p.record_id) THEN RETURN 'binding'; END IF;
  IF EXISTS (SELECT 1 FROM private.source_record_placement WHERE source_record_id=p.record_id) THEN RETURN 'placement findes'; END IF;
  -- Den foldede tekst fra helpostens forekomst.
  SELECT occ.id,occ.rendition_id,occ.verbatim_text INTO v_occ
    FROM private.source_observation o JOIN private.source_record_occurrence occ ON occ.id=o.occurrence_id WHERE o.id=v_obs;
  IF p.tekst IS NULL OR p.tekst='' OR pg_temp.rp_sha(p.tekst) IS DISTINCT FROM k->>'foldet_sha256' THEN RETURN 'foldet tekst'; END IF;
  -- Personen: afdød og med præcis én person_external_id i kilden (writerens krav, efterprøvet før authorize).
  IF NOT EXISTS (SELECT 1 FROM public.person WHERE id=p.person_id AND levende IS FALSE)
     OR (SELECT count(*) FROM public.person_external_id WHERE person_id=p.person_id AND source_id=v_src)<>1 THEN
    RETURN 'person'; END IF;
  v_alias:=(k->>'alias_person_id')::bigint;
  IF v_alias IS NOT NULL AND NOT EXISTS (SELECT 1 FROM public.relation WHERE rolle='samme_som' AND subjekt_type='person'
       AND objekt_type='person' AND ((subjekt_id=p.person_id AND objekt_id=v_alias) OR (subjekt_id=v_alias AND objekt_id=p.person_id))) THEN
    RETURN 'alias'; END IF;
  -- Legacy: personens legacy-narrativer i kilden er netop manifestets (eller ingen), og den er tilbagetrukket.
  IF (SELECT array_agg(n.id ORDER BY n.id) FROM public.narrative n JOIN private.narrative_legacy_publication l ON l.narrative_id=n.id
       WHERE n.subjekt_type='person' AND n.subjekt_id=p.person_id AND l.source_id=v_src)
     IS DISTINCT FROM (CASE WHEN k->>'legacy_narrative_id' IS NULL THEN NULL ELSE ARRAY[(k->>'legacy_narrative_id')::bigint] END) THEN
    RETURN 'legacy'; END IF;
  IF k->>'legacy_narrative_id' IS NOT NULL AND (k->>'legacy_status_foer' IS DISTINCT FROM 'withdrawn'
       OR (SELECT status FROM private.narrative_legacy_publication WHERE narrative_id=(k->>'legacy_narrative_id')::bigint)
          IS DISTINCT FROM k->>'legacy_status_foer') THEN
    RETURN 'legacy'; END IF;
  -- Placementens entry hører til kildens stamtavle-schema og har én canonical-linje.
  IF NOT EXISTS (SELECT 1 FROM public.lineage_scheme s JOIN public.lineage_scheme_entry e ON e.scheme_id=s.id
                  WHERE s.source_id=v_src AND s.kind='stamtavle' AND e.id=(pl->>'scheme_entry_id')::bigint) THEN RETURN 'entry'; END IF;
  BEGIN PERFORM private.lineage_of_entry((pl->>'scheme_entry_id')::bigint);
  EXCEPTION WHEN OTHERS THEN RETURN 'entry'; END;
  -- Overskrifterne: hvert niveau peger på en observation af netop den art fra overskrifts-kørslen i kilden og i
  -- helpostens rendition; menneskeangivne niveauer har ingen observation.
  FOR v_lvl,v_hid IN SELECT key,value FROM jsonb_each_text(pl->'header_ids') LOOP
    IF v_hid !~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN RETURN 'overskrift'; END IF;
    SELECT EXISTS (SELECT 1 FROM private.source_observation o JOIN private.extraction_run r ON r.id=o.extraction_run_id
                     JOIN private.source_record_occurrence occ ON occ.id=o.occurrence_id
                    WHERE o.id=v_hid::uuid AND o.observation_kind='header_'||v_lvl AND r.source_id=v_src AND r.run_key=v_rule
                      AND occ.rendition_id=v_occ.rendition_id) INTO v_ok;
    IF NOT v_ok THEN RETURN 'overskrift'; END IF;
  END LOOP;
  IF EXISTS (SELECT 1 FROM jsonb_array_elements_text(pl->'human_header_levels') x WHERE pl->'header_ids' ? x) THEN
    RETURN 'overskrift'; END IF;
  RETURN NULL;
END $f$;

DO $pre$
DECLARE v_src bigint; v_msha text:=current_setting('rp.manifest_sha'); v_ssha text:=current_setting('rp.svar_sha');
  v_prof private.reimport_writer_profile%ROWTYPE; v_kind text; v_prefix text; i rp_input%ROWTYPE; v_l text; v_o integer:=0;
  x jsonb; pl jsonb; r record; rr rp_post%ROWTYPE; g text[]; v_why text; v_first boolean:=true;
  c_hex constant text:='^[0-9a-f]{64}$';
  c_uuid constant text:='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$';
  c_keys constant text[]:=ARRAY['alias_person_id','foldet_sha256','helpost_observation_id','kort','legacy_narrative_id',
    'legacy_status_foer','linje','mention_id','mention_text_sha256','person_id','placement','record_key'];
  c_pkeys constant text[]:=ARRAY['generation_label_raw','generation_local','header_ids','human_header_levels','kuld_label',
    'scheme_entry_id','section_path'];
BEGIN
  IF current_setting('rp.src') !~ '^-?[0-9]{1,18}$' OR v_msha !~ c_hex OR v_ssha !~ c_hex
     OR current_setting('rp.profile_sha') !~ c_hex OR btrim(current_setting('rp.profile_id'))=''
     OR btrim(current_setting('rp.rule'))='' THEN
    RAISE EXCEPTION 'T_RP_PRE_ARGS';
  END IF;
  v_src:=current_setting('rp.src')::bigint;
  IF current_setting('transaction_isolation')<>'read committed' THEN RAISE EXCEPTION 'T_RP_PRE_ISOLATION'; END IF;
  IF public.current_rolle() IS DISTINCT FROM 'redaktion' THEN RAISE EXCEPTION 'T_RP_PRE_ROLE'; END IF;
  -- DDL'en: operationen og spærringen af legacy-fortrydelsen (§4.5) er kørt; kontrakt v2 (writerens krav).
  IF to_regprocedure('public.red_apply_reimport_record_persona(uuid,text,jsonb)') IS NULL
     OR coalesce(position('NARRATIVE_LEGACY_RECORD_BINDING_EXISTS' IN
          (SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('private.reverse_narrative_publication_event(uuid,text)')))>0,false) IS NOT TRUE
     OR public.narrative_record_contract_version()<>2 THEN
    RAISE EXCEPTION 'T_RP_PRE_DDL';
  END IF;
  IF btrim(coalesce(current_setting('app.change_set_id',true),''))<>'' THEN RAISE EXCEPTION 'T_RP_PRE_GUC'; END IF;
  -- Profilen: den GO-bundne række med persona-prefix; helpost-slagsen er profilens.
  SELECT * INTO v_prof FROM private.reimport_writer_profile WHERE source_id=v_src AND profile_id=current_setting('rp.profile_id');
  IF NOT FOUND OR v_prof.profile_sha256 IS DISTINCT FROM current_setting('rp.profile_sha')
     OR v_prof.profile_sha256 IS DISTINCT FROM private.reimport_canonical_json_sha256(v_prof.writer_config)
     OR coalesce(v_prof.writer_config->>'persona_key_prefix','')='' THEN
    RAISE EXCEPTION 'T_RP_PRE_PROFIL';
  END IF;
  v_kind:=private.writer_config_helpost_kind(v_prof.writer_config); v_prefix:=v_prof.writer_config->>'persona_key_prefix';
  PERFORM set_config('rp.helpost_kind',v_kind,true);
  -- Fase (før låsen; efterprøves under den): ingen batch for manifestet i kilden.
  IF EXISTS (SELECT 1 FROM private.reimport_batch WHERE source_id=v_src AND manifest_sha256=v_msha) THEN
    RAISE EXCEPTION 'T_RP_PRE_FASE';
  END IF;
  -- Filerne er de GO-bundne (psql's `cat` fjerner én afsluttende linjeskift).
  SELECT * INTO i FROM rp_input;
  IF v_msha NOT IN (pg_temp.rp_sha(i.m_text),pg_temp.rp_sha(i.m_text||E'\n'))
     OR v_ssha NOT IN (pg_temp.rp_sha(i.sv_text),pg_temp.rp_sha(i.sv_text||E'\n')) THEN
    RAISE EXCEPTION 'T_RP_PRE_SHA';
  END IF;

  -- Manifestets form: lukkede nøgler og typer pr. linje; kort, linje, post, person og mention er unikke.
  FOR v_l IN SELECT u.l FROM unnest(string_to_array(i.m_text,E'\n')) WITH ORDINALITY AS u(l,ord) ORDER BY u.ord LOOP
    IF btrim(v_l)='' THEN CONTINUE; END IF;
    v_o:=v_o+1;
    BEGIN x:=v_l::jsonb; EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'T_RP_PRE_MANIFEST skema (linje %)',v_o; END;
    pl:=x->'placement';
    IF jsonb_typeof(x)<>'object' OR jsonb_typeof(pl) IS DISTINCT FROM 'object'
       OR ARRAY(SELECT key FROM jsonb_object_keys(x) key ORDER BY key COLLATE "C")<>c_keys
       OR ARRAY(SELECT key FROM jsonb_object_keys(pl) key ORDER BY key COLLATE "C")<>c_pkeys
       OR coalesce(x->>'kort','') !~ '^K[1-9][0-9]{0,5}$'
       OR jsonb_typeof(x->'linje')<>'number' OR (x->>'linje') !~ '^[1-9][0-9]{0,8}$'
       OR jsonb_typeof(x->'person_id')<>'number' OR (x->>'person_id') !~ '^-?[0-9]{1,18}$'
       OR jsonb_typeof(x->'alias_person_id') NOT IN ('number','null')
       OR (jsonb_typeof(x->'alias_person_id')='number' AND (x->>'alias_person_id') !~ '^-?[0-9]{1,18}$')
       OR jsonb_typeof(x->'legacy_narrative_id') NOT IN ('number','null')
       OR (jsonb_typeof(x->'legacy_narrative_id')='number' AND (x->>'legacy_narrative_id') !~ '^-?[0-9]{1,18}$')
       OR jsonb_typeof(x->'legacy_status_foer') NOT IN ('string','null')
       OR (jsonb_typeof(x->'legacy_narrative_id')='null')<>(jsonb_typeof(x->'legacy_status_foer')='null')
       OR jsonb_typeof(x->'record_key')<>'string' OR btrim(x->>'record_key')=''
       OR coalesce(x->>'mention_id','') !~ c_uuid OR coalesce(x->>'helpost_observation_id','') !~ c_uuid
       OR coalesce(x->>'mention_text_sha256','') !~ c_hex OR coalesce(x->>'foldet_sha256','') !~ c_hex
       OR jsonb_typeof(pl->'scheme_entry_id')<>'number' OR (pl->>'scheme_entry_id') !~ '^-?[0-9]{1,18}$'
       OR jsonb_typeof(pl->'generation_local') NOT IN ('number','null')
       OR (jsonb_typeof(pl->'generation_local')='number' AND (pl->>'generation_local') !~ '^-?[0-9]{1,6}$')
       OR jsonb_typeof(pl->'generation_label_raw') NOT IN ('string','null')
       OR jsonb_typeof(pl->'kuld_label') NOT IN ('string','null')
       OR jsonb_typeof(pl->'section_path')<>'array'
       OR EXISTS (SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(pl->'section_path')='array' THEN pl->'section_path' ELSE '[]' END) e
                   WHERE jsonb_typeof(e)<>'string' OR btrim(e#>>'{}')='')
       OR jsonb_typeof(pl->'header_ids')<>'object' OR NOT pl->'header_ids' ? 'linje'
       OR EXISTS (SELECT 1 FROM jsonb_each(CASE WHEN jsonb_typeof(pl->'header_ids')='object' THEN pl->'header_ids' ELSE '{}' END) h
                   WHERE h.key NOT IN ('linje','slaegtled','kuld','aegteskab') OR jsonb_typeof(h.value)<>'string')
       OR jsonb_typeof(pl->'human_header_levels')<>'array'
       OR EXISTS (SELECT 1 FROM jsonb_array_elements(CASE WHEN jsonb_typeof(pl->'human_header_levels')='array' THEN pl->'human_header_levels' ELSE '[]' END) e
                   WHERE jsonb_typeof(e)<>'string' OR e#>>'{}' NOT IN ('slaegtled','kuld','aegteskab'))
       OR (SELECT count(*)<>count(DISTINCT e) FROM jsonb_array_elements_text(CASE WHEN jsonb_typeof(pl->'human_header_levels')='array' THEN pl->'human_header_levels' ELSE '[]' END) e) THEN
      RAISE EXCEPTION 'T_RP_PRE_MANIFEST skema (linje %)',v_o;
    END IF;
    IF EXISTS (SELECT 1 FROM rp_post WHERE kort=x->>'kort' OR linje=(x->>'linje')::integer OR record_key=x->>'record_key'
                OR person_id=(x->>'person_id')::bigint OR mention_id=(x->>'mention_id')::uuid) THEN
      RAISE EXCEPTION 'T_RP_PRE_MANIFEST dublet (linje %)',v_o;
    END IF;
    INSERT INTO rp_post(ord,kort,linje,record_key,person_id,mention_id,k)
      VALUES (v_o,x->>'kort',(x->>'linje')::integer,x->>'record_key',(x->>'person_id')::bigint,(x->>'mention_id')::uuid,x);
  END LOOP;
  IF v_o=0 THEN RAISE EXCEPTION 'T_RP_PRE_MANIFEST tomt'; END IF;

  -- Svarene: første linje bærer manifestets sha; derefter præcis ét J pr. kort og del. Ethvert N stopper alt.
  FOR r IN SELECT l.line,l.ord FROM unnest(string_to_array(replace(i.sv_text,E'\r',''),E'\n')) WITH ORDINALITY AS l(line,ord) ORDER BY l.ord LOOP
    IF v_first THEN
      v_first:=false;
      IF r.line !~ '^#' OR (regexp_match(r.line,'manifest_sha256=([0-9a-f]{64})([^0-9a-f]|$)'))[1] IS DISTINCT FROM v_msha THEN
        RAISE EXCEPTION 'T_RP_PRE_SVAR manifestets sha (linje 1)';
      END IF;
      CONTINUE;
    END IF;
    v_l:=btrim(regexp_replace(r.line,'#.*$',''));
    IF v_l='' THEN CONTINUE; END IF;
    g:=regexp_match(v_l,'^(K[1-9][0-9]{0,5})-(identitet|placement)[[:space:]]+([JN])$');
    IF g IS NULL THEN RAISE EXCEPTION 'T_RP_PRE_SVAR form (linje %)',r.ord; END IF;
    IF NOT EXISTS (SELECT 1 FROM rp_post WHERE kort=g[1]) THEN RAISE EXCEPTION 'T_RP_PRE_SVAR ukendt kort (linje %)',r.ord; END IF;
    IF EXISTS (SELECT 1 FROM rp_svar WHERE kort=g[1] AND del=g[2]) THEN RAISE EXCEPTION 'T_RP_PRE_SVAR dobbelt svar (linje %)',r.ord; END IF;
    IF g[3]<>'J' THEN RAISE EXCEPTION 'T_RP_PRE_SVAR N for % (linje %)',g[1]||'-'||g[2],r.ord; END IF;
    INSERT INTO rp_svar(kort,del,svar) VALUES (g[1],g[2],g[3]);
  END LOOP;
  IF v_first OR EXISTS (SELECT 1 FROM rp_post p CROSS JOIN (VALUES ('identitet'),('placement')) d(del)
                         WHERE NOT EXISTS (SELECT 1 FROM rp_svar s WHERE s.kort=p.kort AND s.del=d.del AND s.svar='J')) THEN
    RAISE EXCEPTION 'T_RP_PRE_SVAR manglende svar';
  END IF;

  -- Låsene i writerens orden, derefter førtilstanden under lås.
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('daa-narrative-record-contract',0));
  PERFORM private.lock_reimport_writer(v_src,current_setting('rp.profile_id'));
  PERFORM pg_advisory_xact_lock_shared(hashtextextended('daa-identity-candidates:'||v_src::text,0));
  UPDATE rp_post p SET record_id=sr.id FROM private.source_record sr WHERE sr.source_id=v_src AND sr.record_key=p.record_key;
  PERFORM 1 FROM private.source_record WHERE id IN (SELECT record_id FROM rp_post) ORDER BY id FOR UPDATE;
  PERFORM 1 FROM private.narrative_record_publication WHERE source_record_id IN (SELECT record_id FROM rp_post) ORDER BY id FOR UPDATE;
  -- Fasen igen (en samtidig ceremoni kan have committet): batch for manifestet, eller en persona med postens nøgle
  -- eller på helpostens mentions (kun helposten: postens øvrige observationer kan have relationspersonas).
  IF EXISTS (SELECT 1 FROM private.reimport_batch WHERE source_id=v_src AND manifest_sha256=v_msha)
     OR EXISTS (SELECT 1 FROM private.source_persona sp JOIN rp_post p ON sp.persona_key=v_prefix||p.record_key WHERE sp.source_id=v_src)
     OR EXISTS (SELECT 1 FROM rp_post p
                  JOIN private.source_mention sm ON sm.observation_id=(p.k->>'helpost_observation_id')::uuid
                  JOIN private.source_persona_mention spm ON spm.mention_id=sm.id)
     OR EXISTS (SELECT 1 FROM rp_post p JOIN private.source_persona_mention spm ON spm.mention_id=p.mention_id) THEN
    RAISE EXCEPTION 'T_RP_PRE_FASE';
  END IF;
  -- Den foldede tekst og writerens payload pr. post (helposten er efterprøvet i rp_tjek).
  UPDATE rp_post p SET helpost=(p.k->>'helpost_observation_id')::uuid,
         tekst=(SELECT btrim((private.relation_fold_raw_text(occ.verbatim_text)).folded)
                  FROM private.source_observation o JOIN private.source_record_occurrence occ ON occ.id=o.occurrence_id
                 WHERE o.id=(p.k->>'helpost_observation_id')::uuid),
         payload=jsonb_build_object('mention_id',p.mention_id,'mention_text_sha256',p.k->>'mention_text_sha256',
           'person_id',p.person_id,'persona_key',v_prefix||p.record_key,'sheet_line',p.linje,'sheet_sha256',v_msha,
           'source_id',v_src,'source_record_key',p.record_key);
  FOR rr IN SELECT * FROM rp_post ORDER BY ord LOOP
    v_why:=pg_temp.rp_tjek(rr,v_kind);
    IF v_why IS NOT NULL THEN RAISE EXCEPTION 'T_RP_PRE_MANIFEST kort % (%)',rr.kort,v_why; END IF;
  END LOOP;
  PERFORM set_config('rp.n',v_o::text,true);
END $pre$;
INSERT INTO rp_hash(navn,foer)
SELECT 'fakta',pg_temp.rp_laeser('fakta',:src) UNION ALL SELECT 'bio',pg_temp.rp_laeser('bio',:src)
UNION ALL SELECT 'synlige',pg_temp.rp_laeser('synlige',:src) UNION ALL SELECT 'koord_andre',pg_temp.rp_koord(:src,true);

-- Skrivning 1: authorize (service_role) → begin → apply pr. post → finalize (redaktøren), i denne transaktion.
DO $persona$
DECLARE v_src bigint:=current_setting('rp.src')::bigint; v_msha text:=current_setting('rp.manifest_sha');
  v_ssha text:=current_setting('rp.svar_sha'); v_n integer:=current_setting('rp.n')::integer; v_els jsonb; v_auth uuid;
  v_batch uuid; v_res jsonb:='{}'::jsonb; e record; v_fin jsonb;
BEGIN
  SELECT jsonb_object_agg('record-persona:'||record_key,payload) INTO v_els FROM rp_post;
  SET LOCAL ROLE service_role;
  v_auth:=public.red_authorize_reimport(v_msha,v_ssha,
    jsonb_build_object('database_name',current_database(),'system_identifier',(pg_control_system()).system_identifier::text)::text,
    v_src,current_setting('rp.profile_id'),current_setting('rp.profile_sha'),
    jsonb_build_object('person_creates',0,'source_evidence',0,'record_personas',v_n),v_els,gen_random_uuid(),
    clock_timestamp()+interval '1 hour');
  SET LOCAL ROLE authenticated;
  v_batch:=public.red_begin_reimport(v_auth,v_msha,v_ssha);
  FOR e IN SELECT key,value FROM jsonb_each(v_els) ORDER BY key COLLATE "C" LOOP
    v_res:=v_res||jsonb_build_object(e.key,public.red_apply_reimport_record_persona(v_batch,e.key,e.value));
  END LOOP;
  v_fin:=public.red_finalize_reimport(v_batch);
  RESET ROLE;
  IF v_fin->>'status' IS DISTINCT FROM 'finalized' OR (v_fin#>>'{counts,record_personas}')::integer IS DISTINCT FROM v_n THEN
    RAISE EXCEPTION 'T_RP_WRITE_BATCH';
  END IF;
  -- Personaen pr. post fra kvitteringen; den skal pege på linjens person og mention.
  UPDATE rp_post p SET persona=(v_res->('record-persona:'||p.record_key)->>'source_persona_id')::uuid;
  IF EXISTS (SELECT 1 FROM rp_post p WHERE p.persona IS NULL
               OR (v_res->('record-persona:'||p.record_key)->>'person_id')::bigint IS DISTINCT FROM p.person_id
               OR (v_res->('record-persona:'||p.record_key)->>'mention_id')::uuid IS DISTINCT FROM p.mention_id) THEN
    RAISE EXCEPTION 'T_RP_WRITE_BATCH kvittering';
  END IF;
  IF btrim(coalesce(current_setting('app.change_set_id',true),''))<>'' THEN RAISE EXCEPTION 'T_RP_WRITE_GUC'; END IF;
END $persona$;

-- Låseordenen: auditlåsen efter finalize og før første identitet (de følgende kald åbner hver deres change_set).
LOCK TABLE public.change_set IN ACCESS EXCLUSIVE MODE;

-- Skrivning 2: identiteterne mod linjens person (kortarkets afgørelse; human_sheet).
DO $identitet$
DECLARE v_msha text:=current_setting('rp.manifest_sha'); v_ssha text:=current_setting('rp.svar_sha'); v_poster jsonb;
  x jsonb; v_ver integer;
BEGIN
  SELECT jsonb_agg(jsonb_build_object('persona',persona,'person',person_id,'kort',kort,'linje',linje) ORDER BY ord) INTO v_poster FROM rp_post;
  FOR x IN SELECT y FROM jsonb_array_elements(v_poster) y LOOP
    PERFORM set_config('app.change_set_id','',true);
    SET LOCAL ROLE authenticated;
    v_ver:=public.red_afgoer_source_persona((x->>'persona')::uuid,0,'same',(x->>'person')::bigint,
      format('kortark %s, linje %s (record_persona)',x->>'kort',x->>'linje'),
      jsonb_build_object('basis','human_sheet','sheet_sha256',v_msha,'rows_sha256',v_ssha,'line',(x->>'linje')::integer));
    PERFORM set_config('app.change_set_id','',true);
    RESET ROLE;
    IF v_ver IS DISTINCT FROM 1
       OR NOT EXISTS (SELECT 1 FROM private.source_persona_identity i WHERE i.source_persona_id=(x->>'persona')::uuid
                        AND i.decision_status='accepted' AND i.canonical_person_id=(x->>'person')::bigint AND i.version=1) THEN
      RAISE EXCEPTION 'T_RP_WRITE_IDENTITET kort %',x->>'kort';
    END IF;
  END LOOP;
END $identitet$;

-- Skrivning 3: placements og ledger (private hjælpefunktioner, som ejer).
DO $placement$
DECLARE v_src bigint:=current_setting('rp.src')::bigint; v_msha text:=current_setting('rp.manifest_sha');
  v_ssha text:=current_setting('rp.svar_sha'); v_navn text:=current_setting('rp.navn'); r record; pl jsonb; v_rp uuid;
  v_pp uuid; v_foer integer; v_ver integer; v_ev jsonb;
BEGIN
  FOR r IN SELECT * FROM rp_post ORDER BY ord LOOP
    pl:=r.k->'placement';
    v_ev:=jsonb_build_object('basis','human_sheet','sheet_sha256',v_msha,'rows_sha256',v_ssha,'line',r.linje,
      'kort',r.kort,'record_key',r.record_key,'decided_by_name',v_navn);
    v_rp:=private.write_record_placement(r.record_id,(pl->>'scheme_entry_id')::bigint,
      jsonb_build_object('printed_number',NULL,'generation_local',pl->'generation_local','generation_global',NULL,
        'generation_label_raw',pl->'generation_label_raw','kuld_label',pl->'kuld_label','section_path',pl->'section_path'),
      (pl#>>'{header_ids,linje}')::uuid,
      v_ev||jsonb_build_object('rule_version',current_setting('rp.rule'),'header_ids',pl->'header_ids',
        'human_header_levels',pl->'human_header_levels'));
    v_pp:=private.write_persona_placement(r.persona,v_rp,r.helpost,
      v_ev||jsonb_build_object('rule_version','placement-membership-v1','record_placement_id',v_rp));
    SELECT max(version) INTO v_foer FROM private.legacy_placement_disposition WHERE person_id=r.person_id AND source_id=v_src;
    v_ver:=private.record_legacy_disposition(r.person_id,v_src,'mapped',v_rp,
      v_ev||jsonb_build_object('rule_version','placement-membership-v1'));
    IF v_ver IS DISTINCT FROM coalesce(v_foer,0)+1
       OR NOT EXISTS (SELECT 1 FROM private.legacy_placement_disposition_current d WHERE d.person_id=r.person_id
                        AND d.source_id=v_src AND d.is_current AND d.disposition='mapped' AND d.placement_id=v_rp) THEN
      RAISE EXCEPTION 'T_RP_WRITE_LEDGER kort %',r.kort;
    END IF;
    UPDATE rp_post SET rp=v_rp,pp=v_pp,ledger_foer=v_foer WHERE ord=r.ord;
  END LOOP;
  IF private.placement_header_violations(v_src)<>0 THEN
    RAISE EXCEPTION 'T_RP_WRITE_HEADER n=%',private.placement_header_violations(v_src);
  END IF;
END $placement$;
ANALYZE private.source_record_placement, private.source_record_placement_decision, private.source_persona_placement,
  private.source_persona_placement_decision, private.legacy_placement_disposition;

-- Skrivning 4: medlemskab. Forhåndsvisningens eligible-mængde skal være præcis manifestets personer; ellers stopper
-- ceremonien (en promovering for kilden ville ramme andre end kortenes personer).
DO $medlemskab$
DECLARE v_src bigint:=current_setting('rp.src')::bigint; v_n integer:=current_setting('rp.n')::integer; v_pv jsonb;
  v_exp bigint[]; v_set bigint[]; v_items integer; v_prom integer;
BEGIN
  v_exp:=ARRAY(SELECT person_id FROM rp_post ORDER BY person_id);
  PERFORM set_config('app.change_set_id','',true);
  SET LOCAL ROLE authenticated;
  v_pv:=public.red_preview_placement_memberships(v_src);
  RESET ROLE;
  SELECT count(*),array_agg((i->>'person_id')::bigint ORDER BY (i->>'person_id')::bigint) INTO v_items,v_set
    FROM jsonb_array_elements(v_pv->'items') i WHERE (i->>'eligible')::boolean;
  IF v_items<>v_n OR v_set IS DISTINCT FROM v_exp THEN
    RAISE EXCEPTION 'T_RP_PRE_MEDLEMSKAB eligible=% (forventet %)',v_items,v_n;
  END IF;
  SET LOCAL ROLE authenticated;
  v_prom:=public.red_promote_placement_memberships(v_src,v_pv->>'preview_sha256');
  PERFORM set_config('app.change_set_id','',true);
  RESET ROLE;
  IF v_prom IS DISTINCT FROM v_n
     OR EXISTS (SELECT 1 FROM rp_post p WHERE NOT EXISTS (
                  SELECT 1 FROM public.person_lineage_membership l WHERE l.person_id=p.person_id
                     AND l.source_basis->>'persona_placement_id'=p.pp::text AND private.membership_is_current(l.person_id,l.lineage_id))) THEN
    RAISE EXCEPTION 'T_RP_WRITE_MEDLEMSKAB n=%',v_prom;
  END IF;
  -- Kæden er nu klar til kladden: identitet og placement giver accepted_identity (eligible) for hver post.
  IF EXISTS (SELECT 1 FROM rp_post p, LATERAL private.narrative_publication_state(p.person_id,v_src,p.record_key) s
              WHERE s#>>'{authority,kind}' IS DISTINCT FROM 'accepted_identity'
                 OR s#>>'{authority,eligibility_status}' IS DISTINCT FROM 'eligible') THEN
    RAISE EXCEPTION 'T_RP_WRITE_STATE';
  END IF;
END $medlemskab$;
ANALYZE public.person_lineage_membership, public.person_slaegt_membership, public.change_set, public.change_event;

-- Skrivning 5: kladderne sidst (den generelle narrativwriter som redaktør); tilstands-sha'en læses som ejer lige før.
DO $kladde$
DECLARE v_src bigint:=current_setting('rp.src')::bigint; v_poster jsonb; x jsonb; v_h text; v_res jsonb;
BEGIN
  SELECT jsonb_agg(jsonb_build_object('kort',kort,'person',person_id,'k',record_key,'t',tekst) ORDER BY ord) INTO v_poster FROM rp_post;
  FOR x IN SELECT y FROM jsonb_array_elements(v_poster) y LOOP
    v_h:=private.narrative_record_state((x->>'person')::bigint,v_src,x->>'k',false)->>'state_sha256';
    PERFORM set_config('app.change_set_id','',true);
    SET LOCAL ROLE authenticated;
    v_res:=public.red_upsert_person_narrative_record((x->>'person')::bigint,v_src,x->>'k',x->>'t',false,v_h);
    PERFORM set_config('app.change_set_id','',true);
    RESET ROLE;
    IF v_res IS NULL THEN RAISE EXCEPTION 'T_RP_WRITE_KLADDE kort %',x->>'kort'; END IF;
  END LOOP;
END $kladde$;

DO $post$
DECLARE v_src bigint:=current_setting('rp.src')::bigint; v_n integer:=current_setting('rp.n')::integer;
  v_prefix text; v_personas integer; v_ident integer; v_pl integer; v_med integer; v_kl integer; v_navn text; h record;
BEGIN
  IF btrim(coalesce(current_setting('app.change_set_id',true),''))<>'' THEN RAISE EXCEPTION 'T_RP_POST_GUC'; END IF;
  SELECT writer_config->>'persona_key_prefix' INTO v_prefix FROM private.reimport_writer_profile
   WHERE source_id=v_src AND profile_id=current_setting('rp.profile_id');
  -- Tilstanden: kladden er den eksakte binding (existing_exact_binding, eligible) for hver post.
  IF EXISTS (SELECT 1 FROM rp_post p, LATERAL private.narrative_publication_state(p.person_id,v_src,p.record_key) s
              WHERE s#>>'{authority,kind}' IS DISTINCT FROM 'existing_exact_binding'
                 OR s#>>'{authority,eligibility_status}' IS DISTINCT FROM 'eligible') THEN
    RAISE EXCEPTION 'T_RP_POST_STATE';
  END IF;
  -- Rækkerne pr. post: én persona (nøgle og mention), accepteret identitet til linjens person, record- og
  -- persona-placement accepteret, gældende medlemskab, én kladde med den foldede tekst om personen.
  SELECT count(*) FILTER (WHERE (SELECT count(*) FROM private.source_persona_mention spm WHERE spm.mention_id=p.mention_id)=1
                            AND EXISTS (SELECT 1 FROM private.source_persona sp WHERE sp.id=p.persona AND sp.source_id=v_src
                                          AND sp.persona_key=v_prefix||p.record_key)),
         count(*) FILTER (WHERE EXISTS (SELECT 1 FROM private.source_persona_identity i WHERE i.source_persona_id=p.persona
                                          AND i.decision_status='accepted' AND i.canonical_person_id=p.person_id)),
         count(*) FILTER (WHERE EXISTS (SELECT 1 FROM private.source_record_placement_current rp WHERE rp.id=p.rp
                                          AND rp.decision_status='accepted' AND rp.source_record_id=p.record_id)
                            AND EXISTS (SELECT 1 FROM private.source_persona_placement_current pp WHERE pp.id=p.pp
                                          AND pp.decision_status='accepted' AND pp.placement_role='principal_member')),
         count(*) FILTER (WHERE EXISTS (SELECT 1 FROM public.person_lineage_membership l WHERE l.person_id=p.person_id
                                          AND l.source_basis->>'persona_placement_id'=p.pp::text
                                          AND private.membership_is_current(l.person_id,l.lineage_id))),
         count(*) FILTER (WHERE (SELECT count(*) FROM private.narrative_record_publication b
                                   JOIN public.narrative n ON n.id=b.narrative_id
                                  WHERE b.source_record_id=p.record_id AND b.status='draft' AND n.subjekt_type='person'
                                    AND n.subjekt_id=p.person_id AND n.tekst=p.tekst)=1
                            AND (SELECT count(*) FROM private.narrative_record_publication b WHERE b.source_record_id=p.record_id)=1)
    INTO v_personas,v_ident,v_pl,v_med,v_kl FROM rp_post p;
  IF v_personas<>v_n OR v_ident<>v_n OR v_pl<>v_n OR v_med<>v_n OR v_kl<>v_n THEN
    RAISE EXCEPTION 'T_RP_POST_RAEKKER personas=% identiteter=% placements=% medlemskab=% kladder=% (forventet %)',
      v_personas,v_ident,v_pl,v_med,v_kl,v_n;
  END IF;
  -- Legacy-teksterne er stadig tilbagetrukne.
  IF EXISTS (SELECT 1 FROM rp_post p JOIN private.narrative_legacy_publication l
               ON l.narrative_id=(p.k->>'legacy_narrative_id')::bigint WHERE l.status<>'withdrawn') THEN
    RAISE EXCEPTION 'T_RP_POST_LEGACY';
  END IF;
  IF private.placement_header_violations(v_src)<>0 THEN RAISE EXCEPTION 'T_RP_POST_HEADER'; END IF;
  -- Læserne er uændrede, indtil projektejeren selv publicerer: FAKTA, BIO, kildens synlige tekster og de andre
  -- kilders koordinater (kildens egne koordinater ændres af placementen).
  FOR h IN SELECT navn,foer FROM rp_hash LOOP
    IF h.foer IS DISTINCT FROM (CASE h.navn WHEN 'koord_andre' THEN pg_temp.rp_koord(v_src,true)
                                            ELSE pg_temp.rp_laeser(h.navn,v_src) END) THEN
      RAISE EXCEPTION 'T_RP_POST_%',upper(h.navn);
    END IF;
  END LOOP;
  -- Kvitteringen skrives sidst: en change_set med kilden som subjekt.
  v_navn:=format('T_RP_OK personas=%s identiteter=%s placements=%s medlemskab=%s kladder=%s',v_personas,v_ident,v_pl,v_med,v_kl);
  PERFORM public.begin_change_set('record_persona_ceremoni',v_navn,'source',v_src);
  PERFORM set_config('app.change_set_id','',true);
  PERFORM set_config('rp.kvittering',v_navn,true);
END $post$;
SELECT current_setting('rp.kvittering') AS kvittering \gset
COMMIT;
\echo :kvittering
