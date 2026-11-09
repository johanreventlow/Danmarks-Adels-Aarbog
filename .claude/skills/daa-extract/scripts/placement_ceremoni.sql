-- Trin 6d-1 (plan Task 7): placement- og medlemskabsceremonien for én kilde, generaliseret fra fix_150_placement.sql
-- (som er frosset). I ÉN transaktion: linjeskema (nye entries + canonical/historical_alias), overskrifter, record- og
-- persona-placements, legacy-ledger for kildens rækker, medlemskaber via promotions-RPC'en og revalidering af
-- kildens publicerede biografier, så læseren aldrig ser `stale_published`. Kildeparametriseret; nævner ingen udgave.
-- Fejlkoder PLC_PRE_* (intet skrevet), PLC_WRITE_*/PLC_MID_* (under skrivningen), PLC_POST_* (efterbetingelser);
-- enhver fejl ruller hele transaktionen tilbage. Kvittering: `PLC_OK entries=… headers=… placements=… persona=…
-- ledger_mapped=… memberships=… revalideret=… corroborated=… conflict=… human_levels=…`.
--
-- Records slås op på source_record.record_key (manifestets nøgle). Personen pr. record er den accepterede identitet for
-- recordens eneste primary-persona på helposten. Helposten findes med skemaets regel private.record_helpost_status
-- (status ok): den accepterede forekomst, hvis eneste top-observation har profilens helpost_observation_kind
-- (argumentet helpost_kind — `person` i 1939, `person_post` i 2018-20); recordens øvrige accepterede forekomster
-- (1939's fakta-, ægteskabs- og relationsforekomster med egne rod-observationer) ligger inde i dens tegnspænd.
-- Bindinger og publiceringstilstande slås op via recorden (narrative_record_publication → source_record), aldrig via
-- person_external_id.record_key, som kun i 2018-20 svarer til recordens nøgle.
--
-- Filerne indlæses klientside (\set … `cat`), aldrig \copy; de kan nævne levende personer, så runneren sender stdout og
-- stderr til en privat fil.
--   manifest  (build_header_manifest.py): {header_rule_version, headers[], placements[], invariants{4}}
--   mapping   (lineage_mapping_sheet.py approvals): {sheet_sha256, token_sha256, entries:[{code, label_sha256,
--             sort_order, canonical:{source_id,kode}|null, aliases:[{source_id,kode}], parkeret}]}
--   approvals (kontrolarkets godkendelser, kontrakt v3): {manifest_sha256, approvals:[{record_key, printed_number?, reviewer}],
--             gruppekort:[{id, value, reviewer}], kontrol?:{model, brief_sha256, svar_sha256}}; reviewer = model|human.
-- Gruppekort (decisions 2026-11-09): en overskrift, som guiden kender, men renditionen ikke har, bekræftes af
-- projektejeren mod den trykte side; value skal være lig guide_value. En post under kort er skrivbar, når alle dens
-- kort er godkendt og dens øvrige årsager er ingen eller godkendt med en record-approval. Værdien (kuld_label eller
-- generation_local/-label) kommer fra kortet; evidensen bærer human_header_levels (manifestets liste) og human_review.
-- Strukturkort (ikke_parret, nummer_tabt_i_rendition, ikke_alignet): record-approval med nummer; placementen bruger
-- manifestets nærmeste overskrifter (naermeste_*). stamme_generation_usikker godkendes uden nummer (manifestets værdier).
-- Brug: psql -X -At -v ON_ERROR_STOP=1 -v actor=<uuid> -v src=<kilde> -v go=<GO-kode>
--   -v manifest_path=<fil> -v manifest_sha=<sha256 af filen> -v mapping_path=<fil> -v mapping_sha=<arkets sheet_sha256>
--   -v mapping_token_sha=<token_sha256> -v mapping_file_sha=<sha256 af mapping-filen>
--   -v approvals_path=<fil> -v approvals_sha=<GO-bundet sha256 af filen> -v approvals_file_sha=<sha256 af filen>
--   -v rendition_sha=<renditionens content_sha256> -v header_rule_version=<regelversion> -v helpost_kind=<observationstype>
--   -v expect_headers=N -v expect_human_levels=N -v expect_entries=N -v expect_placements=N -v expect_persona_placements=N -v expect_bindings=N
--   -v expect_published=N -v expect_revalidated=N -v expect_ledger_mapped=N -v expect_ledger_retained=N
--   -v expect_memberships=N -v expect_corroborated=N -v expect_conflict=N -v expect_laeser_1939=<uaendret|placement>
--   -v expect_koord_2018_20=<KOORD_2018_20 fra maal_trin6d1.sql i fase foer> -f placement_ceremoni.sql
-- Forventningerne: expect_entries = kildens stamtavle-entries efter linjeskemaet (eksisterende + nye, ikke-parkerede);
-- expect_bindings = bindinger på records, der får persona-placement; expect_published = kildens publicerede bindinger;
-- expect_revalidated = publicerede bindinger på records, der får record-placement; expect_corroborated/expect_conflict =
-- komponenttal i hele basen efter ceremonien (membership_component_states).
-- Linjerækkefølgen: mappingens sort_order (bogens orden) gælder for alle ikke-parkerede entries, også eksisterende;
-- kildens eksisterende entries skal alle stå i mappingen og flyttes til mappingens plads i linjeskemaets change_set.
\set QUIET on
\set ON_ERROR_STOP on
\set m `cat :'manifest_path'`
\set mp `cat :'mapping_path'`
\set a `cat :'approvals_path'`
BEGIN;
SET LOCAL statement_timeout = '15min';
DO $timeout$ BEGIN IF current_setting('statement_timeout')<>'15min' THEN RAISE EXCEPTION 'PLC_PRE_TIMEOUT'; END IF; END $timeout$;
SELECT set_config('request.jwt.claim.sub', :'actor', true), set_config('plc.src', :'src', true),
       set_config('plc.go', :'go', true), set_config('plc.manifest_sha', :'manifest_sha', true),
       set_config('plc.mapping_sha', :'mapping_sha', true), set_config('plc.mapping_token_sha', :'mapping_token_sha', true),
       set_config('plc.approvals_sha', :'approvals_sha', true), set_config('plc.rendition_sha', :'rendition_sha', true),
       set_config('plc.mapping_file_sha', :'mapping_file_sha', true),
       set_config('plc.approvals_file_sha', :'approvals_file_sha', true),
       set_config('plc.rule', :'header_rule_version', true), set_config('plc.helpost_kind', :'helpost_kind', true),
       set_config('plc.expect', json_build_object('headers', :'expect_headers'::int, 'entries', :'expect_entries'::int,
         'human', :'expect_human_levels'::int,
         'placements', :'expect_placements'::int, 'persona', :'expect_persona_placements'::int,
         'bindings', :'expect_bindings'::int, 'published', :'expect_published'::int,
         'revalidated', :'expect_revalidated'::int, 'ledger_mapped', :'expect_ledger_mapped'::int,
         'ledger_retained', :'expect_ledger_retained'::int, 'memberships', :'expect_memberships'::int,
         'corroborated', :'expect_corroborated'::int, 'conflict', :'expect_conflict'::int,
         'laeser', :'expect_laeser_1939', 'koord', :'expect_koord_2018_20')::text, true) \g /dev/null
CREATE TEMP TABLE plc_input ON COMMIT DROP AS
SELECT :'m'::text AS m_text, :'mp'::text AS mp_text, :'a'::text AS a_text;
-- Fælles navn til evidens og change_sets (ingen udgave i logikken).
SELECT set_config('plc.navn', 'placement-ceremoni (GO '||current_setting('plc.go')||')', true) \g /dev/null

-- Recordsættet: én række pr. manifest-placement med recorden, helposten, hovedperson-personaen og dens identitet.
-- skriv = record-placement (machine_ok eller godkendt/kortdækket, gren ikke parkeret); persona = også persona-placement.
CREATE TEMP TABLE plc_rec (record_key text PRIMARY KEY, p jsonb NOT NULL, ap jsonb, entry_code text, parkeret boolean,
  record_id uuid, n_helpost integer, helpost uuid, n_primary integer, persona_id uuid, identity_status text,
  person_id bigint, skriv boolean NOT NULL DEFAULT false, persona boolean NOT NULL DEFAULT false, basis text,
  entry_id bigint, rp uuid, pp uuid,
  -- kandidat = skrivbar bortset fra parkering; hids/vals = placementens header_ids og værdier (efter kort/strukturkort);
  -- human = evidensens human_header_levels (kun gruppekort-poster); review = evidensens human_review.
  kandidat boolean NOT NULL DEFAULT false, hids jsonb, vals jsonb, human jsonb, review jsonb,
  -- rev = evidensens læser (reviewer_kind model|human|blandet, og modelkontrollen når en model læste).
  rev jsonb) ON COMMIT DROP;
-- Linjeskemaets plan: én række pr. mapping-entry.
CREATE TEMP TABLE plc_entry (code text PRIMARY KEY, e jsonb NOT NULL, parkeret boolean NOT NULL, eksisterende bigint,
  label text, sort_order integer, canonical_lineage bigint, alias_lineages bigint[]) ON COMMIT DROP;
-- Ledgerens plan: én række pr. person_external_id-række i kilden.
-- foer_* = den gældende række før ceremonien (5c-1 skrev v1 retained_legacy for alle kilder); record_legacy_disposition
-- skriver ingen ny version, når disposition, placement og legacy-hash er uændrede.
CREATE TEMP TABLE plc_ledger (person_id bigint PRIMARY KEY, disposition text NOT NULL, grund text, record_key text,
  foer_version integer, foer_disposition text) ON COMMIT DROP;
-- Kildens bindinger og deres publiceringstilstand før skrivningen (via recorden).
CREATE TEMP TABLE plc_binding (binding_id uuid PRIMARY KEY, record_id uuid, record_key text, person_id bigint,
  status text, eligibility text, blocked boolean) ON COMMIT DROP;
-- Paritetshashes før/efter (læsere, andre kilders placements/medlemskaber/publiceringer/ledger, koordinater).
CREATE TEMP TABLE plc_paritet (laeser text PRIMARY KEY, foer text, efter text) ON COMMIT DROP;

-- Koordinat-hash (samme udtryk som maal_trin6d1.sql): p_andre = rækkerne med source_id <> kilden, ellers kildens egne.
CREATE FUNCTION pg_temp.plc_koord(p_src bigint,p_andre boolean) RETURNS text LANGUAGE sql AS $f$
  SELECT md5(coalesce(string_agg(concat_ws('|',quote_nullable(c.person_id),quote_nullable(c.source_id),
           quote_nullable(c.legacy_line_code),quote_nullable(c.printed_number),quote_nullable(c.printed_number_label),
           quote_nullable(c.generation_local),quote_nullable(c.generation_global),quote_nullable(c.kuld_label),
           quote_nullable(c.provenance_kind)),E'\n' ORDER BY c.person_id,c.source_id),''))
    FROM public.public_person_source_coordinates() c
   WHERE (c.source_id<>p_src)=p_andre;
$f$;

-- Paritetsmålingen. fix_150's fem læsere (redaktørlæserne som redaktør, de offentlige som ejer; regen_person_visning i
-- et savepoint, der rulles tilbage) for kildens personer (legacy-rækker og identiteter), plus andre kilders
-- placements, medlemskaber, publiceringstilstand og ledger, og koordinatrækkerne (andre kilder / kilden selv).
CREATE FUNCTION pg_temp.plc_paritet(p_kol text) RETURNS void LANGUAGE plpgsql AS $f$
DECLARE v_src bigint:=current_setting('plc.src')::bigint; v_persons bigint[]; v_grid text; v_match text; v_fam text;
  v_bio text; v_regen text; v_pl text; v_mem text; v_pub text; v_led text;
BEGIN
  SELECT array_agg(DISTINCT x ORDER BY x) INTO v_persons FROM (
    SELECT person_id AS x FROM public.person_external_id WHERE source_id=v_src
    UNION SELECT person_id FROM plc_rec WHERE person_id IS NOT NULL) y;
  SET LOCAL ROLE authenticated;
  v_grid:=(SELECT md5(string_agg(g::text, '|' ORDER BY g::text)) FROM public.red_person_grid() g);
  v_match:=md5(public.red_match_personer()::text);
  RESET ROLE;
  v_fam:=(SELECT md5(string_agg(s::text, '|' ORDER BY s::text))
            FROM public.public_family_sources(ARRAY(SELECT id FROM public.family ORDER BY id)) s);
  v_bio:=(SELECT md5(string_agg(s::text, '|' ORDER BY s::text)) FROM public.public_person_bio_source_versions_v2(v_persons) s);
  BEGIN
    PERFORM public.regen_person_visning(x) FROM unnest(v_persons) x;
    v_regen:=(SELECT md5(string_agg(row(p.id,p.visning_navn,p.visning_foedt,p.visning_doed,p.visning_titel,
                                        p.visning_efternavn,p.visning_fuldt_navn)::text, '|' ORDER BY p.id))
                FROM public.person p WHERE p.id=ANY(v_persons));
    RAISE EXCEPTION 'PLC_PARITET_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM<>'PLC_PARITET_ROLLBACK' THEN RAISE; END IF;
  END;
  v_pl:=(SELECT md5(coalesce(string_agg(x, E'\n' ORDER BY x COLLATE "C"),'')) FROM (
           SELECT concat_ws('|','r',pc.id,pc.version,pc.decision_status,pc.scheme_entry_id,pc.printed_number) AS x
             FROM private.source_record_placement_current pc JOIN private.source_record r ON r.id=pc.source_record_id
            WHERE r.source_id<>v_src
           UNION ALL
           SELECT concat_ws('|','p',pc.id,pc.version,pc.decision_status,pc.placement_role,pc.record_placement_id)
             FROM private.source_persona_placement_current pc JOIN private.source_record_placement rp ON rp.id=pc.record_placement_id
             JOIN private.source_record r ON r.id=rp.source_record_id
            WHERE r.source_id<>v_src) z);
  v_mem:=(SELECT md5(coalesce(string_agg(x, E'\n' ORDER BY x COLLATE "C"),'')) FROM (
           SELECT concat_ws('|','l',person_id,lineage_id,role,valid_from,valid_to,source_basis::text) AS x
             FROM public.person_lineage_membership WHERE source_basis->>'source_id' IS DISTINCT FROM v_src::text
           UNION ALL
           SELECT concat_ws('|','s',person_id,slaegt_id,membership_kind,source_basis::text)
             FROM public.person_slaegt_membership WHERE source_basis->>'source_id' IS DISTINCT FROM v_src::text) z);
  v_pub:=(SELECT md5(coalesce(string_agg(concat_ws('|',b.id,s->>'publication_status',s->>'eligibility_status',
                                                   s->>'state_sha256'), E'\n' ORDER BY b.id::text COLLATE "C"),''))
            FROM private.narrative_record_publication b
            JOIN private.source_record sr ON sr.id=b.source_record_id AND sr.source_id<>v_src
            JOIN public.narrative n ON n.id=b.narrative_id AND n.subjekt_type='person',
                 LATERAL private.narrative_record_state(n.subjekt_id, sr.source_id, sr.record_key) s);
  v_led:=(SELECT md5(coalesce(string_agg(concat_ws('|',person_id,source_id,version,disposition,placement_id,is_current),
                                         E'\n' ORDER BY person_id,source_id),''))
            FROM private.legacy_placement_disposition_current WHERE source_id<>v_src);
  EXECUTE format('INSERT INTO plc_paritet(laeser,%1$I) SELECT * FROM unnest(%2$L::text[],%3$L::text[])
                  ON CONFLICT (laeser) DO UPDATE SET %1$I=excluded.%1$I', p_kol,
    ARRAY['red_person_grid','red_match_personer','public_family_sources','public_person_bio_source_versions_v2',
          'regen_person_visning','placements_andre','memberships_andre','publicering_andre','ledger_andre',
          'koord_andre','koord_kilde'],
    ARRAY[coalesce(v_grid,'tom'),coalesce(v_match,'tom'),coalesce(v_fam,'tom'),coalesce(v_bio,'tom'),
          coalesce(v_regen,'tom'),v_pl,v_mem,coalesce(v_pub,'tom'),v_led,pg_temp.plc_koord(v_src,true),
          pg_temp.plc_koord(v_src,false)]);
END $f$;

DO $pre$
DECLARE v_src bigint:=current_setting('plc.src')::bigint; e jsonb:=current_setting('plc.expect')::jsonb;
  v_rule text:=current_setting('plc.rule'); i plc_input%ROWTYPE; m jsonb; mp jsonb; a jsonb; v_n bigint;
  v_scheme bigint; v_slaegt bigint; rr record; v_lin bigint; v_ids bigint[];
  c_invariants constant text[]:=ARRAY['en_overskrift_pr_gruppe','gruppekort_daekker_overskriftsaarsager',
                                      'record_keys_unikke','section_path_nr_unik','segmenter_paritet'];
  c_godkendelige constant text[]:=ARRAY['nr_ikke_fortloebende','slaegtled_ikke_monoton','gruppe_flere_familier',
                                        'uenig:legacy_nr','uenig:legacy_linje','nummer_tabt_i_rendition','ikke_parret',
                                        'ikke_alignet','stamme_generation_usikker'];
  c_struktur constant text[]:=ARRAY['ikke_parret','nummer_tabt_i_rendition','ikke_alignet'];
  v_gk jsonb; v_o text[]; v_r text[]; v_struct boolean; v_kort_ok boolean; v_kand boolean; v_hids jsonb; v_vals jsonb;
  v_entry text; v_kort jsonb; v_c jsonb; v_val text; v_rev text[]; v_rv text;
  c_uden_nummer constant text[]:=ARRAY['uden_post','ikke_parret','nummer_tabt_i_rendition'];
BEGIN
  IF e->>'laeser' NOT IN ('uaendret','placement') OR coalesce(e->>'koord','') !~ '^[0-9a-f]{32}$'
     OR btrim(v_rule)='' OR btrim(current_setting('plc.go'))='' OR btrim(current_setting('plc.helpost_kind'))='' THEN
    RAISE EXCEPTION 'PLC_PRE_ARGS';
  END IF;
  IF public.current_rolle() IS DISTINCT FROM 'redaktion' THEN RAISE EXCEPTION 'PLC_PRE_ROLE'; END IF;
  -- DDL'en fra Task 3-5 er kørt (samme markører som maal_trin6d1.sql).
  IF NOT (coalesce(position('i.canonical_person_id=p_person_id' IN
                     (SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('private.record_legacy_disposition(bigint,bigint,text,uuid,jsonb)')))>0,false)
          AND to_regprocedure('private.membership_component_states()') IS NOT NULL
          AND coalesce(position('printed_number IS NULL' IN
                     (SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('public.public_person_source_coordinates()')))>0,false)
          AND coalesce(position('PLACEMENT_MEMBERSHIP_FOREIGN_SOURCE' IN
                     (SELECT prosrc FROM pg_proc WHERE oid=to_regprocedure('public.red_promote_placement_memberships(bigint,text)')))>0,false)) THEN
    RAISE EXCEPTION 'PLC_PRE_DDL';
  END IF;
  IF btrim(coalesce(current_setting('app.change_set_id',true),''))<>'' THEN RAISE EXCEPTION 'PLC_PRE_GUC'; END IF;
  -- Fase: intet skrevet for kilden endnu (genkørsel stopper her). Andre kilders rækker er ligegyldige. Kildens
  -- ledger-rækker tæller ikke: 5c-1's ceremoni skrev retained_legacy (v1) for alle kilders legacy-rækker.
  IF EXISTS (SELECT 1 FROM private.source_record_placement rp JOIN private.source_record r ON r.id=rp.source_record_id
              WHERE r.source_id=v_src)
     OR EXISTS (SELECT 1 FROM public.person_lineage_membership WHERE source_basis->>'source_id'=v_src::text)
     OR EXISTS (SELECT 1 FROM public.person_slaegt_membership WHERE source_basis->>'source_id'=v_src::text) THEN
    RAISE EXCEPTION 'PLC_PRE_FASE';
  END IF;
  -- Filerne er de GO-bundne: indholdet har den bundne sha (psql's `cat` fjerner én afsluttende linjeskift), arkets og
  -- token-filens sha står i mappingen, og godkendelserne hører til manifestet.
  SELECT * INTO i FROM plc_input;
  -- Mapping- og godkendelsesfilerne selv (ikke kun arkets/token-filens sha): runnerens måling af filernes bytes.
  IF current_setting('plc.mapping_file_sha') NOT IN (encode(extensions.digest(i.mp_text,'sha256'),'hex'),
                                                     encode(extensions.digest(i.mp_text||E'\n','sha256'),'hex')) THEN
    RAISE EXCEPTION 'PLC_PRE_MAPPING_FIL';
  END IF;
  IF current_setting('plc.approvals_file_sha') NOT IN (encode(extensions.digest(i.a_text,'sha256'),'hex'),
                                                       encode(extensions.digest(i.a_text||E'\n','sha256'),'hex')) THEN
    RAISE EXCEPTION 'PLC_PRE_APPROVALS_FIL';
  END IF;
  IF current_setting('plc.manifest_sha') NOT IN (encode(extensions.digest(i.m_text,'sha256'),'hex'),
                                                 encode(extensions.digest(i.m_text||E'\n','sha256'),'hex'))
     OR current_setting('plc.approvals_sha') NOT IN (encode(extensions.digest(i.a_text,'sha256'),'hex'),
                                                     encode(extensions.digest(i.a_text||E'\n','sha256'),'hex')) THEN
    RAISE EXCEPTION 'PLC_PRE_SHA';
  END IF;
  m:=i.m_text::jsonb; mp:=i.mp_text::jsonb; a:=i.a_text::jsonb;
  IF mp->>'sheet_sha256' IS DISTINCT FROM current_setting('plc.mapping_sha')
     OR mp->>'token_sha256' IS DISTINCT FROM current_setting('plc.mapping_token_sha') THEN
    RAISE EXCEPTION 'PLC_PRE_SHA';
  END IF;
  -- Manifestet: regelversionen er den bundne, og præcis de fire kørselsinvarianter er sande (fail-closed).
  IF m->>'header_rule_version' IS DISTINCT FROM v_rule OR jsonb_typeof(m->'invariants')<>'object'
     OR (SELECT array_agg(k ORDER BY k COLLATE "C") FROM jsonb_object_keys(m->'invariants') k) IS DISTINCT FROM c_invariants
     OR EXISTS (SELECT 1 FROM jsonb_each(m->'invariants') x WHERE x.value<>'true'::jsonb)
     OR jsonb_typeof(m->'placements')<>'array' OR jsonb_typeof(m->'headers')<>'array' THEN
    RAISE EXCEPTION 'PLC_PRE_INVARIANTS';
  END IF;
  -- Renditionen: præcis én for kilden med det bundne indhold.
  IF (SELECT count(*) FROM private.source_rendition WHERE source_id=v_src AND content_sha256=current_setting('plc.rendition_sha'))<>1 THEN
    RAISE EXCEPTION 'PLC_PRE_RENDITION';
  END IF;

  -- Godkendelserne (kontrolarkets svar, kontrakt v3): hører til manifestet; record-approvals pr. nøgle højst én og for
  -- en nøgle i manifestet (reglerne pr. post står i planløkken nedenfor).
  v_gk:=coalesce(a->'gruppekort','[]'::jsonb);
  IF a->>'manifest_sha256' IS DISTINCT FROM current_setting('plc.manifest_sha') OR jsonb_typeof(a->'approvals')<>'array'
     OR (SELECT count(*) FROM jsonb_array_elements(a->'approvals') x)
          <>(SELECT count(DISTINCT x->>'record_key') FROM jsonb_array_elements(a->'approvals') x)
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(a->'approvals') x
                 WHERE NOT EXISTS (SELECT 1 FROM jsonb_array_elements(m->'placements') p WHERE p->>'record_key'=x->>'record_key')) THEN
    RAISE EXCEPTION 'PLC_PRE_APPROVALS';
  END IF;
  -- Gruppekortene: hvert id højst én gang, findes i manifestet (med én guide-værdi), og projektejerens værdi fra siden
  -- er lig guidens (det er kontrollen); slægtled er et heltal.
  IF jsonb_typeof(v_gk)<>'array'
     OR (SELECT count(*) FROM jsonb_array_elements(v_gk) x)<>(SELECT count(DISTINCT x->>'id') FROM jsonb_array_elements(v_gk) x) THEN
    RAISE EXCEPTION 'PLC_PRE_GRUPPEKORT';
  END IF;
  FOR rr IN SELECT x AS gk FROM jsonb_array_elements(v_gk) x LOOP
    SELECT count(DISTINCT (k->'guide_value')::text||'|'||coalesce(k->>'niveau','')), min(k::text)::jsonb INTO v_n, v_kort
      FROM jsonb_array_elements(m->'placements') p, jsonb_array_elements(coalesce(p->'gruppekort','[]'::jsonb)) k
     WHERE k->>'id'=rr.gk->>'id';
    IF v_n<>1 OR jsonb_typeof(rr.gk->'value') NOT IN ('string','number')
       OR v_kort->>'niveau' NOT IN ('slaegtled','kuld')
       OR (rr.gk->'value')#>>'{}' IS DISTINCT FROM (v_kort->'guide_value')#>>'{}'
       OR (v_kort->>'niveau'='slaegtled' AND (rr.gk->'value')#>>'{}' !~ '^[0-9]+$') THEN
      RAISE EXCEPTION 'PLC_PRE_GRUPPEKORT %', rr.gk->>'id';
    END IF;
  END LOOP;
  -- Læseren (decisions 2026-11-09): hver godkendelse og hvert kort siger, om en model (mod PDF-siden) eller
  -- projektejeren læste; har en model læst noget, beskriver kontrol-objektet kørslen (model, briefens og svarenes sha).
  IF EXISTS (SELECT 1 FROM (SELECT x FROM jsonb_array_elements(a->'approvals') x UNION ALL
                            SELECT x FROM jsonb_array_elements(v_gk) x) y
              WHERE jsonb_typeof(y.x->'reviewer') IS DISTINCT FROM 'string' OR y.x->>'reviewer' NOT IN ('model','human')) THEN
    RAISE EXCEPTION 'PLC_PRE_REVIEWER';
  END IF;
  IF EXISTS (SELECT 1 FROM (SELECT x FROM jsonb_array_elements(a->'approvals') x UNION ALL
                            SELECT x FROM jsonb_array_elements(v_gk) x) y WHERE y.x->>'reviewer'='model')
     AND (jsonb_typeof(a->'kontrol') IS DISTINCT FROM 'object'
          OR EXISTS (SELECT 1 FROM unnest(ARRAY['model','brief_sha256','svar_sha256']) f
                      WHERE jsonb_typeof(a->'kontrol'->f) IS DISTINCT FROM 'string' OR btrim(a->'kontrol'->>f)='')) THEN
    RAISE EXCEPTION 'PLC_PRE_KONTROL';
  END IF;

  -- Mappingen (linjearkets afgørelser) og kildens stamtavle-schema.
  SELECT count(*), min(id), min(slaegt_id) INTO v_n, v_scheme, v_slaegt FROM public.lineage_scheme
   WHERE source_id=v_src AND kind='stamtavle';
  IF v_n<>1 THEN RAISE EXCEPTION 'PLC_PRE_SCHEME'; END IF;
  IF jsonb_typeof(mp->'entries')<>'array'
     OR (SELECT count(*) FROM jsonb_array_elements(mp->'entries') x)
          <>(SELECT count(DISTINCT x->>'code') FROM jsonb_array_elements(mp->'entries') x)
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(mp->'entries') x
                 WHERE btrim(coalesce(x->>'code',''))='' OR jsonb_typeof(x->'parkeret')<>'boolean'
                    OR jsonb_typeof(x->'aliases')<>'array') THEN
    RAISE EXCEPTION 'PLC_PRE_MAPPING form';
  END IF;
  INSERT INTO plc_entry(code,e,parkeret,eksisterende)
  SELECT x->>'code', x, (x->>'parkeret')::boolean,
         (SELECT le.id FROM public.lineage_scheme_entry le WHERE le.scheme_id=v_scheme AND le.code=x->>'code')
    FROM jsonb_array_elements(mp->'entries') x;
  FOR rr IN SELECT * FROM plc_entry ORDER BY code COLLATE "C" LOOP
    IF rr.parkeret THEN
      -- En parkeret gren får ingen entry; en eksisterende entry kan ikke parkeres.
      IF rr.eksisterende IS NOT NULL OR jsonb_typeof(rr.e->'canonical') IS DISTINCT FROM 'null' OR jsonb_array_length(rr.e->'aliases')<>0 THEN
        RAISE EXCEPTION 'PLC_PRE_MAPPING parkeret %', rr.code;
      END IF;
      CONTINUE;
    END IF;
    -- Linjerne slås op på (source_id, kode); de skal høre til kildens slægt.
    SELECT count(*), min(l.id) INTO v_n, v_lin FROM public.lineage l
     WHERE l.source_id=(rr.e#>>'{canonical,source_id}')::bigint AND l.kode=rr.e#>>'{canonical,kode}' AND l.slaegt_id=v_slaegt;
    IF v_n<>1 THEN RAISE EXCEPTION 'PLC_PRE_MAPPING canonical %', rr.code; END IF;
    SELECT array_agg(l.id ORDER BY l.id), count(*) INTO v_ids, v_n
      FROM jsonb_array_elements(rr.e->'aliases') al
      JOIN public.lineage l ON l.source_id=(al->>'source_id')::bigint AND l.kode=al->>'kode' AND l.slaegt_id=v_slaegt;
    IF v_n<>jsonb_array_length(rr.e->'aliases') OR v_lin=ANY(coalesce(v_ids,'{}'))
       OR cardinality(coalesce(v_ids,'{}'))<>(SELECT count(DISTINCT x) FROM unnest(coalesce(v_ids,'{}')) x) THEN
      RAISE EXCEPTION 'PLC_PRE_MAPPING alias %', rr.code;
    END IF;
    IF rr.eksisterende IS NOT NULL THEN
      -- Eksisterende entries oprettes ikke igen; deres canonical skal være den angivne, og der tilføjes intet.
      BEGIN
        IF private.lineage_of_entry(rr.eksisterende)<>v_lin OR jsonb_array_length(rr.e->'aliases')<>0 THEN
          RAISE EXCEPTION 'PLC_PRE_MAPPING eksisterende %', rr.code;
        END IF;
      EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'PLC_PRE_MAPPING eksisterende %', rr.code;
      END;
      UPDATE plc_entry SET canonical_lineage=v_lin, alias_lineages='{}',
             sort_order=CASE WHEN jsonb_typeof(rr.e->'sort_order')='number' AND rr.e->>'sort_order' ~ '^[0-9]+$'
                             THEN (rr.e->>'sort_order')::integer END
       WHERE code=rr.code;
      CONTINUE;
    END IF;
    -- Ny entry: labelen er grenens linjeoverskrift i manifestet med arkets label-hash.
    UPDATE plc_entry SET canonical_lineage=v_lin, alias_lineages=coalesce(v_ids,'{}'),
           sort_order=CASE WHEN jsonb_typeof(rr.e->'sort_order')='number' AND rr.e->>'sort_order' ~ '^[0-9]+$'
                           THEN (rr.e->>'sort_order')::integer END,
           label=(SELECT min(h->>'verbatim_text') FROM jsonb_array_elements(m->'headers') h
                   WHERE h->>'kind'='header_linje' AND h#>>'{parsed,entry_code}'=rr.code
                     AND h->>'verbatim_sha256'=rr.e->>'label_sha256'
                     AND h->>'verbatim_sha256'=encode(extensions.digest(h->>'verbatim_text','sha256'),'hex'))
     WHERE code=rr.code;
  END LOOP;
  -- Nye entries har en label; alle ikke-parkerede (også eksisterende) har et heltal >= 0 som sort_order, unikt inden
  -- for mappingen (DB'ens nuværende værdier flyttes i linjeskemaets skridt); hver eksisterende entry står i mappingen.
  IF EXISTS (SELECT 1 FROM plc_entry WHERE NOT parkeret AND eksisterende IS NULL AND (label IS NULL OR btrim(label)=''))
     OR EXISTS (SELECT 1 FROM plc_entry WHERE NOT parkeret AND (sort_order IS NULL OR sort_order<0))
     OR (SELECT count(*) FROM plc_entry WHERE NOT parkeret)
          <>(SELECT count(DISTINCT sort_order) FROM plc_entry WHERE NOT parkeret) THEN
    RAISE EXCEPTION 'PLC_PRE_MAPPING label/sort_order';
  END IF;
  IF EXISTS (SELECT 1 FROM public.lineage_scheme_entry le WHERE le.scheme_id=v_scheme
               AND NOT EXISTS (SELECT 1 FROM plc_entry x WHERE x.eksisterende=le.id AND NOT x.parkeret)) THEN
    RAISE EXCEPTION 'PLC_PRE_MAPPING eksisterende mangler';
  END IF;

  -- Recordsættet. Hver manifest-nøgle findes som record i kilden.
  INSERT INTO plc_rec(record_key,p,ap,entry_code)
  SELECT p->>'record_key', p, (SELECT x FROM jsonb_array_elements(a->'approvals') x WHERE x->>'record_key'=p->>'record_key'),
         p->>'entry_code'
    FROM jsonb_array_elements(m->'placements') p;
  UPDATE plc_rec f SET record_id=sr.id FROM private.source_record sr WHERE sr.source_id=v_src AND sr.record_key=f.record_key;
  IF EXISTS (SELECT 1 FROM plc_rec WHERE record_id IS NULL) THEN
    RAISE EXCEPTION 'PLC_PRE_RECORDS n=%', (SELECT count(*) FROM plc_rec WHERE record_id IS NULL);
  END IF;
  -- Planen pr. post. Årsagerne deles i overskriftsårsager (overskrift_ikke_fundet:<niveau>, kun dækket af godkendte
  -- gruppekort) og øvrige (dækket af en record-approval efter reglerne). En record-approval kræver en unresolved post med
  -- mindst én øvrig årsag, alle godkendelige; strukturposter kræver et nummer og en nærmeste linjeoverskrift, andre
  -- poster må ikke angive nummer og skal have en linjeoverskrift. En approval, der ikke gør posten skrivbar, stopper.
  FOR rr IN SELECT * FROM plc_rec ORDER BY record_key COLLATE "C" LOOP
    v_o:=ARRAY(SELECT split_part(k,':',2) FROM jsonb_array_elements_text(coalesce(rr.p->'reasons','[]'::jsonb)) k
                WHERE k LIKE 'overskrift_ikke_fundet:%');
    v_r:=ARRAY(SELECT k FROM jsonb_array_elements_text(coalesce(rr.p->'reasons','[]'::jsonb)) k
                WHERE k NOT LIKE 'overskrift_ikke_fundet:%');
    v_struct:=v_r && c_struktur;
    IF rr.ap IS NOT NULL AND (rr.p->>'status' IS DISTINCT FROM 'unresolved' OR cardinality(v_r)=0
       OR NOT v_r <@ c_godkendelige
       OR (v_struct AND (jsonb_typeof(rr.ap->'printed_number') IS DISTINCT FROM 'string'
                         OR btrim(rr.ap->>'printed_number')='' OR coalesce(rr.p#>>'{naermeste_header_ids,linje}','')=''))
       OR (NOT v_struct AND ((rr.ap ? 'printed_number' AND jsonb_typeof(rr.ap->'printed_number')<>'null')
                             OR coalesce(rr.p#>>'{header_ids,linje}','')=''))) THEN
      RAISE EXCEPTION 'PLC_PRE_APPROVALS %', rr.record_key;
    END IF;
    v_kort_ok:=NOT EXISTS (SELECT 1 FROM unnest(v_o) lv
                            WHERE lv NOT IN ('slaegtled','kuld')
                               OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(coalesce(rr.p->'gruppekort','[]'::jsonb)) k
                                               WHERE k->>'niveau'=lv
                                                 AND EXISTS (SELECT 1 FROM jsonb_array_elements(v_gk) g WHERE g->>'id'=k->>'id')));
    v_kand:=rr.p->>'status'='machine_ok'
            OR (rr.p->>'status'='unresolved' AND cardinality(v_o)+cardinality(v_r)>0 AND v_kort_ok
                AND (cardinality(v_r)=0 OR rr.ap IS NOT NULL));
    IF rr.ap IS NOT NULL AND NOT v_kand THEN RAISE EXCEPTION 'PLC_PRE_APPROVALS virker ikke %', rr.record_key; END IF;
    IF NOT v_kand THEN CONTINUE; END IF;
    v_rev:=CASE WHEN rr.ap IS NULL THEN '{}'::text[] ELSE ARRAY[rr.ap->>'reviewer'] END;
    IF v_struct THEN
      v_hids:=rr.p->'naermeste_header_ids';
      v_entry:=rr.p->>'naermeste_entry_code';
      v_vals:=jsonb_build_object('printed_number',rr.ap->>'printed_number',
        'generation_local',rr.p->'naermeste_generation_local','generation_global',NULL,
        'generation_label_raw',(SELECT h#>'{parsed,label_raw}' FROM jsonb_array_elements(m->'headers') h
                                 WHERE h->>'element_id'=v_hids->>'slaegtled'),
        'kuld_label',rr.p->'naermeste_kuld_label',
        'section_path',to_jsonb(ARRAY(SELECT v_hids->>lv FROM unnest(ARRAY['linje','slaegtled','kuld']) WITH ORDINALITY u(lv,o)
                                       WHERE v_hids ? lv ORDER BY o)));
    ELSE
      v_hids:=rr.p->'header_ids';
      v_entry:=rr.p->>'entry_code';
      v_vals:=jsonb_build_object('printed_number',rr.p->'printed_number','generation_local',rr.p->'generation_local',
        'generation_global',rr.p->'generation_global','generation_label_raw',rr.p->'generation_label_raw',
        'kuld_label',rr.p->'kuld_label','section_path',coalesce(rr.p->'section_path','[]'::jsonb));
      v_kort:='[]'::jsonb;
      FOR v_c IN SELECT k FROM jsonb_array_elements(coalesce(rr.p->'gruppekort','[]'::jsonb)) k LOOP
        SELECT g->'value'#>>'{}', g->>'reviewer' INTO v_val, v_rv FROM jsonb_array_elements(v_gk) g WHERE g->>'id'=v_c->>'id';
        IF v_val IS NULL THEN CONTINUE; END IF;
        v_rev:=v_rev||v_rv;
        IF v_c->>'niveau'='kuld' THEN
          v_vals:=v_vals||jsonb_build_object('kuld_label',v_val);
        ELSE
          v_vals:=v_vals||jsonb_build_object('generation_local',v_val::integer,'generation_label_raw',v_val);
        END IF;
        v_kort:=v_kort||jsonb_build_array(jsonb_build_object('id',v_c->>'id','value',v_val,
                                                             'guide_line_sha256',v_c->>'guide_line_sha256','reviewer',v_rv));
      END LOOP;
      IF jsonb_array_length(v_kort)>0 THEN
        UPDATE plc_rec SET human=coalesce(rr.p->'human_header_levels','[]'::jsonb),
               review=jsonb_build_object('gruppekort',v_kort,'approvals_sha256',current_setting('plc.approvals_sha'))
         WHERE record_key=rr.record_key;
      END IF;
    END IF;
    -- basis: maskinel; model_page_review når kun en model har læst; ellers human_group_review (læseren står i rev).
    UPDATE plc_rec SET kandidat=true, entry_code=v_entry, hids=v_hids, vals=v_vals,
           basis=CASE WHEN rr.p->>'status'='machine_ok' THEN 'machine'
                      WHEN cardinality(v_rev)>0 AND v_rev<@ARRAY['model'] THEN 'model_page_review'
                      ELSE 'human_group_review' END,
           rev=CASE WHEN rr.p->>'status'='machine_ok' THEN NULL
                    ELSE jsonb_build_object('reviewer_kind',CASE WHEN v_rev<@ARRAY['model'] THEN 'model'
                                                                 WHEN v_rev<@ARRAY['human'] THEN 'human' ELSE 'blandet' END)
                         ||CASE WHEN 'model'=ANY(v_rev) THEN jsonb_build_object('kontrol',a->'kontrol') ELSE '{}'::jsonb END END
     WHERE record_key=rr.record_key;
  END LOOP;
  -- Mappingen dækker hver gren i de poster, der kan skrives.
  IF EXISTS (SELECT 1 FROM plc_rec f WHERE f.kandidat
               AND (f.entry_code IS NULL OR NOT EXISTS (SELECT 1 FROM plc_entry x WHERE x.code=f.entry_code))) THEN
    RAISE EXCEPTION 'PLC_PRE_MAPPING gren mangler';
  END IF;
  IF (SELECT count(*) FROM public.lineage_scheme_entry WHERE scheme_id=v_scheme)
     +(SELECT count(*) FROM plc_entry WHERE NOT parkeret AND eksisterende IS NULL)<>(e->>'entries')::bigint THEN
    RAISE EXCEPTION 'PLC_PRE_ENTRIES';
  END IF;
  UPDATE plc_rec f SET parkeret=x.parkeret FROM plc_entry x WHERE x.code=f.entry_code;
  UPDATE plc_rec SET skriv=true WHERE kandidat AND parkeret IS FALSE;
  -- Helpost og hovedperson-persona (materialiseret med statistik, jf. fix_150's anker-view-plan).
  CREATE TEMP TABLE plc_helpost ON COMMIT DROP AS
  -- Skemaets helpost-regel (status ok); none/ambiguous/outside giver ingen række, altså n_helpost=0 (fail-closed).
  SELECT f.record_id, hs.observation_id AS obs
    FROM plc_rec f, LATERAL private.record_helpost_status(f.record_id, current_setting('plc.helpost_kind')) hs
   WHERE hs.status='ok';
  ANALYZE plc_helpost;
  CREATE TEMP TABLE plc_primary ON COMMIT DROP AS
  SELECT h.record_id, spm.persona_id, i2.decision_status, i2.canonical_person_id
    FROM plc_helpost h
    JOIN private.source_mention sm ON sm.observation_id=h.obs
    JOIN private.source_persona_mention spm ON spm.mention_id=sm.id AND spm.mention_role='primary'
    LEFT JOIN private.source_persona_identity i2 ON i2.source_persona_id=spm.persona_id;
  ANALYZE plc_primary;
  UPDATE plc_rec f SET n_helpost=(SELECT count(*) FROM plc_helpost h WHERE h.record_id=f.record_id),
         helpost=(SELECT min(h.obs::text)::uuid FROM plc_helpost h WHERE h.record_id=f.record_id),
         n_primary=(SELECT count(*) FROM plc_primary x WHERE x.record_id=f.record_id),
         persona_id=(SELECT min(x.persona_id::text)::uuid FROM plc_primary x WHERE x.record_id=f.record_id);
  UPDATE plc_rec f SET identity_status=x.decision_status,
         person_id=CASE WHEN x.decision_status='accepted' THEN x.canonical_person_id END
    FROM plc_primary x WHERE f.n_primary=1 AND x.record_id=f.record_id;
  IF EXISTS (SELECT 1 FROM plc_rec WHERE skriv AND n_helpost<>1) THEN
    RAISE EXCEPTION 'PLC_PRE_RECORDS helpost n=%', (SELECT count(*) FROM plc_rec WHERE skriv AND n_helpost<>1);
  END IF;
  IF EXISTS (SELECT 1 FROM plc_rec WHERE skriv AND n_primary>1) THEN RAISE EXCEPTION 'PLC_PRE_PERSONA'; END IF;
  -- Persona-placement kun for præcis én primary-persona med accepteret identitet (afgørelse 5).
  UPDATE plc_rec SET persona=true WHERE skriv AND n_primary=1 AND person_id IS NOT NULL;
  -- Overskrifterne: hver skrevet post har en linjeoverskrift (header_linje i manifestet), og dens header_ids peger på
  -- manifestets overskrifter.
  IF jsonb_array_length(m->'headers')<>(e->>'headers')::int
     OR EXISTS (SELECT 1 FROM plc_rec f WHERE f.skriv AND (jsonb_typeof(f.hids) IS DISTINCT FROM 'object'
                  OR coalesce(f.hids->>'linje','')=''
                  OR NOT EXISTS (SELECT 1 FROM jsonb_array_elements(m->'headers') h
                                  WHERE h->>'element_id'=f.hids->>'linje' AND h->>'kind'='header_linje')
                  OR EXISTS (SELECT 1 FROM jsonb_each_text(f.hids) k
                              WHERE NOT EXISTS (SELECT 1 FROM jsonb_array_elements(m->'headers') h
                                                 WHERE h->>'element_id'=k.value)))) THEN
    RAISE EXCEPTION 'PLC_PRE_HEADERS';
  END IF;
  -- Menneskebekræftede niveauer: kun slaegtled/kuld, aldrig også et id i header_ids, og hvert godkendt korts niveau er
  -- med; en post uden godkendt kort har ingen (ellers ville nærmeste-reglens undtagelse gælde uden evidens).
  IF EXISTS (SELECT 1 FROM plc_rec f WHERE f.skriv AND (
               (f.human IS NULL AND jsonb_array_length(coalesce(f.p->'human_header_levels','[]'::jsonb))<>0)
               OR (f.human IS NOT NULL AND (jsonb_typeof(f.human)<>'array' OR jsonb_array_length(f.human)=0
                   OR EXISTS (SELECT 1 FROM jsonb_array_elements(f.human) x
                               WHERE jsonb_typeof(x)<>'string' OR x#>>'{}' NOT IN ('slaegtled','kuld')
                                  OR f.hids ? (x#>>'{}'))
                   OR EXISTS (SELECT 1 FROM jsonb_array_elements(f.review->'gruppekort') g
                               JOIN jsonb_array_elements(f.p->'gruppekort') k ON k->>'id'=g->>'id'
                              WHERE NOT f.human ? (k->>'niveau')))))) THEN
    RAISE EXCEPTION 'PLC_PRE_HUMAN';
  END IF;
  IF (SELECT count(*) FROM plc_rec WHERE skriv AND human IS NOT NULL)<>(e->>'human')::bigint THEN
    RAISE EXCEPTION 'PLC_PRE_HUMAN_LEVELS n=%', (SELECT count(*) FROM plc_rec WHERE skriv AND human IS NOT NULL);
  END IF;
  -- Unikhed over alt, der skrives (maskinelle og godkendte): med nummer højst én pr. (gren, slægtled, gruppe, nummer);
  -- uden nummer (stamfædre) højst én pr. (gren, slægtled, gruppe).
  IF EXISTS (SELECT 1 FROM plc_rec WHERE skriv
              GROUP BY entry_code, vals->>'generation_local', vals->>'kuld_label', vals->>'printed_number'
             HAVING count(*)>1) THEN
    RAISE EXCEPTION 'PLC_PRE_UNIK';
  END IF;
  -- Ingen to personas, der får placement, peger på samme person (promotionen ville se en konflikt).
  IF (SELECT count(*) FROM plc_rec WHERE persona)<>(SELECT count(DISTINCT person_id) FROM plc_rec WHERE persona) THEN
    RAISE EXCEPTION 'PLC_PRE_SAME_PERSON';
  END IF;
  -- Ingen af personerne har allerede et linje- eller slægtsmedlemskab (målt 0; promotionen rører aldrig fremmede rækker).
  IF EXISTS (SELECT 1 FROM plc_rec f WHERE f.persona
               AND (EXISTS (SELECT 1 FROM public.person_lineage_membership l WHERE l.person_id=f.person_id)
                    OR EXISTS (SELECT 1 FROM public.person_slaegt_membership s WHERE s.person_id=f.person_id))) THEN
    RAISE EXCEPTION 'PLC_PRE_MEMBERSHIP_OVERLAP';
  END IF;

  -- Bindingerne via recorden: identitet = binding for hver binding på en record, der får persona-placement (en placement
  -- for en anden person ville blokere bindingen).
  CREATE TEMP TABLE plc_bind_all ON COMMIT DROP AS
  SELECT b.id AS binding_id, sr.id AS record_id, sr.record_key, n.subjekt_id AS person_id
    FROM private.narrative_record_publication b
    JOIN private.source_record sr ON sr.id=b.source_record_id AND sr.source_id=v_src
    JOIN public.narrative n ON n.id=b.narrative_id AND n.subjekt_type='person';
  ANALYZE plc_bind_all;
  IF EXISTS (SELECT 1 FROM plc_bind_all b JOIN plc_rec f ON f.record_id=b.record_id
              WHERE f.persona AND f.person_id IS DISTINCT FROM b.person_id) THEN
    RAISE EXCEPTION 'PLC_PRE_IDENTITY n=%', (SELECT count(*) FROM plc_bind_all b JOIN plc_rec f ON f.record_id=b.record_id
                                              WHERE f.persona AND f.person_id IS DISTINCT FROM b.person_id);
  END IF;
  SELECT count(*) INTO v_n FROM plc_bind_all b JOIN plc_rec f ON f.record_id=b.record_id WHERE f.persona;
  IF v_n<>(e->>'bindings')::bigint THEN RAISE EXCEPTION 'PLC_PRE_BINDINGS n=%', v_n; END IF;
  -- Publiceringstilstand før: præcis de forventede publicerede, ingen forældede, og alle publicerede på records, der
  -- placeres (dem revalideringen rører), er tilladte. En publiceret biografi for en staged person på en record, der
  -- ikke placeres (prods 963/967 i 1939's oversigtszone, baseline ved kontrakt-cutover), røres ikke og står uændret.
  INSERT INTO plc_binding
  SELECT b.binding_id, b.record_id, b.record_key, b.person_id, s->>'publication_status', s->>'eligibility_status',
         (s->>'blocking_reason') IS NOT NULL
    FROM plc_bind_all b, LATERAL private.narrative_record_state(b.person_id, v_src, b.record_key) s;
  IF (SELECT count(*) FROM plc_binding WHERE status='published')<>(e->>'published')::bigint
     OR EXISTS (SELECT 1 FROM plc_binding WHERE status='stale_published')
     OR EXISTS (SELECT 1 FROM plc_binding b JOIN plc_rec f ON f.record_id=b.record_id AND f.skriv,
                       LATERAL private.narrative_record_state(b.person_id, v_src, b.record_key) s
                 WHERE b.status='published'
                   AND (NOT coalesce((s#>>'{publication_state,publication_policy,publication_allowed}')::boolean,false)
                        OR s->>'published_text_sha256' IS NULL)) THEN
    RAISE EXCEPTION 'PLC_PRE_PUBLISHED';
  END IF;

  -- Antal: placements, persona-placements og (dermed) medlemskaber.
  IF (SELECT count(*) FROM plc_rec WHERE skriv)<>(e->>'placements')::bigint THEN
    RAISE EXCEPTION 'PLC_PRE_PLACEMENTS n=%', (SELECT count(*) FROM plc_rec WHERE skriv);
  END IF;
  IF (SELECT count(*) FROM plc_rec WHERE persona)<>(e->>'persona')::bigint THEN
    RAISE EXCEPTION 'PLC_PRE_PERSONA_PLACEMENTS n=%', (SELECT count(*) FROM plc_rec WHERE persona);
  END IF;
  IF (SELECT count(*) FROM plc_rec WHERE persona)<>(e->>'memberships')::bigint THEN RAISE EXCEPTION 'PLC_PRE_MEMBERSHIPS'; END IF;
  IF (SELECT count(*) FROM plc_binding f JOIN plc_rec p ON p.record_id=f.record_id WHERE f.status='published' AND p.skriv)
       <>(e->>'revalidated')::bigint THEN
    RAISE EXCEPTION 'PLC_PRE_REVALIDATED';
  END IF;

  -- Ledgerens plan for kildens legacy-rækker: mapped, når identitetsvejen holder (personen er accepteret identitet for
  -- en persona, der får principal_member-placement); ellers retained_legacy med første gældende grund:
  -- ingen_identitet (ingen primary-persona i kilden med accepteret identitet til personen) → parkeret_gren →
  -- ingen_nummereret_post (posten mangler nummer: uden_post/ikke_parret/nummer_tabt_i_rendition, ikke godkendt) →
  -- ingen_placement.
  INSERT INTO plc_ledger(person_id,disposition,grund,record_key,foer_version,foer_disposition)
  SELECT pe.person_id,
         CASE WHEN f.record_key IS NOT NULL THEN 'mapped' ELSE 'retained_legacy' END,
         CASE WHEN f.record_key IS NOT NULL THEN NULL
              WHEN NOT EXISTS (SELECT 1 FROM plc_primary x WHERE x.decision_status='accepted'
                                 AND x.canonical_person_id=pe.person_id) THEN 'ingen_identitet'
              WHEN EXISTS (SELECT 1 FROM plc_primary x JOIN plc_rec g ON g.record_id=x.record_id
                            WHERE x.decision_status='accepted' AND x.canonical_person_id=pe.person_id AND g.parkeret) THEN 'parkeret_gren'
              WHEN EXISTS (SELECT 1 FROM plc_primary x JOIN plc_rec g ON g.record_id=x.record_id
                            WHERE x.decision_status='accepted' AND x.canonical_person_id=pe.person_id AND g.ap IS NULL
                              AND EXISTS (SELECT 1 FROM jsonb_array_elements_text(g.p->'reasons') k WHERE k=ANY(c_uden_nummer)))
                THEN 'ingen_nummereret_post'
              ELSE 'ingen_placement' END,
         f.record_key, d.version, d.disposition
    FROM public.person_external_id pe
    LEFT JOIN plc_rec f ON f.persona AND f.person_id=pe.person_id
    LEFT JOIN private.legacy_placement_disposition_current d ON d.person_id=pe.person_id AND d.source_id=v_src
   WHERE pe.source_id=v_src;
  IF (SELECT count(*) FROM plc_ledger WHERE disposition='mapped')<>(e->>'ledger_mapped')::bigint
     OR (SELECT count(*) FROM plc_ledger WHERE disposition='retained_legacy')<>(e->>'ledger_retained')::bigint THEN
    RAISE EXCEPTION 'PLC_PRE_LEDGER mapped=% retained=%', (SELECT count(*) FROM plc_ledger WHERE disposition='mapped'),
      (SELECT count(*) FROM plc_ledger WHERE disposition='retained_legacy');
  END IF;
END $pre$;
SELECT pg_temp.plc_paritet('foer') \g /dev/null

-- Skrivning 1: linjeskemaet under eget change_set (nye entries + canonical/historical_alias; parkerede grene får ingen).
DO $linje$
DECLARE v_src bigint:=current_setting('plc.src')::bigint; v_scheme bigint; v_slaegt bigint; r record; v_entry bigint;
  v_lin bigint; v_n integer:=0; v_off integer;
BEGIN
  SELECT id, slaegt_id INTO v_scheme, v_slaegt FROM public.lineage_scheme WHERE source_id=v_src AND kind='stamtavle';
  PERFORM public.begin_change_set('placement_lineage_scheme', current_setting('plc.navn')||': linjeskema for kilde '||v_src);
  -- Eksisterende entries flyttes til mappingens sort_order før de nye indsættes. UNIQUE(scheme_id,sort_order) kan ikke
  -- udskydes og sort_order>=0, så i to faser: først over både nuværende og planlagte værdier, så til de endelige.
  SELECT greatest(coalesce((SELECT max(sort_order) FROM public.lineage_scheme_entry WHERE scheme_id=v_scheme),0),
                  coalesce((SELECT max(sort_order) FROM plc_entry WHERE NOT parkeret),0))+1 INTO v_off;
  UPDATE public.lineage_scheme_entry le SET sort_order=v_off+x.sort_order
    FROM plc_entry x WHERE x.eksisterende=le.id AND le.sort_order<>x.sort_order;
  UPDATE public.lineage_scheme_entry le SET sort_order=x.sort_order
    FROM plc_entry x WHERE x.eksisterende=le.id AND le.sort_order<>x.sort_order;
  FOR r IN SELECT * FROM plc_entry WHERE NOT parkeret AND eksisterende IS NULL ORDER BY sort_order LOOP
    INSERT INTO public.lineage_scheme_entry(scheme_id,slaegt_id,code,label,sort_order)
      VALUES (v_scheme,v_slaegt,r.code,r.label,r.sort_order) RETURNING id INTO v_entry;
    INSERT INTO public.lineage_scheme_entry_lineage(entry_id,lineage_id,slaegt_id,relation_kind)
      VALUES (v_entry,r.canonical_lineage,v_slaegt,'canonical');
    FOREACH v_lin IN ARRAY r.alias_lineages LOOP
      INSERT INTO public.lineage_scheme_entry_lineage(entry_id,lineage_id,slaegt_id,relation_kind)
        VALUES (v_entry,v_lin,v_slaegt,'historical_alias');
    END LOOP;
    v_n:=v_n+1;
  END LOOP;
  PERFORM set_config('app.change_set_id','',true);
  -- Hver entry i kildens schema har nu præcis én canonical-linje.
  FOR v_entry IN SELECT e.id FROM public.lineage_scheme_entry e WHERE e.scheme_id=v_scheme LOOP
    BEGIN PERFORM private.lineage_of_entry(v_entry);
    EXCEPTION WHEN OTHERS THEN RAISE EXCEPTION 'PLC_WRITE_LINEAGE entry %', v_entry; END;
  END LOOP;
  IF (SELECT count(*) FROM public.lineage_scheme_entry WHERE scheme_id=v_scheme)
       <>(current_setting('plc.expect')::jsonb->>'entries')::bigint THEN
    RAISE EXCEPTION 'PLC_WRITE_ENTRIES n=%', v_n;
  END IF;
  UPDATE plc_rec f SET entry_id=e.id FROM public.lineage_scheme_entry e
   WHERE e.scheme_id=v_scheme AND e.code=f.entry_code AND f.skriv;
  IF EXISTS (SELECT 1 FROM plc_rec WHERE skriv AND entry_id IS NULL) THEN RAISE EXCEPTION 'PLC_WRITE_ENTRIES poster'; END IF;
END $linje$;

-- Skrivning 2: overskrifter, record- og persona-placements, ledger (private funktioner, som ejer).
DO $skriv$
DECLARE v_src bigint:=current_setting('plc.src')::bigint; e jsonb:=current_setting('plc.expect')::jsonb;
  m jsonb:=(SELECT m_text::jsonb FROM plc_input); v_rend uuid; v_n integer; r record; v_ids jsonb; v_ev jsonb; k text;
  v_key text:=current_setting('plc.rule'); v_navn text:=current_setting('plc.navn'); v_vals jsonb;
BEGIN
  SELECT id INTO v_rend FROM private.source_rendition WHERE source_id=v_src AND content_sha256=current_setting('plc.rendition_sha');
  v_n:=private.write_header_evidence(v_src, v_rend, jsonb_build_object('run_key',v_key,'schema_version','header-manifest-v1',
    'extractor_version','build_header_manifest.py','profile_version',v_key,'input_sha256',current_setting('plc.rendition_sha'),
    'manifest',jsonb_build_object('manifest_sha256',current_setting('plc.manifest_sha'),'go',current_setting('plc.go'))),
    m->'headers');
  IF v_n<>(e->>'headers')::int THEN RAISE EXCEPTION 'PLC_WRITE_HEADERS n=%', v_n; END IF;
  FOR r IN SELECT * FROM plc_rec WHERE skriv ORDER BY record_key COLLATE "C" LOOP
    v_ids:='{}'::jsonb;
    FOR k IN SELECT jsonb_object_keys(r.hids) LOOP
      v_ids:=v_ids||jsonb_build_object(k, private.header_observation_uuid(v_rend, v_key,
               split_part(r.hids->>k, ':', 2)::integer));
    END LOOP;
    v_vals:=r.vals;
    v_ev:=jsonb_build_object('rule_version',v_key,'header_ids',v_ids,'basis',r.basis,'record_key',r.record_key,
      'manifest_sha256',current_setting('plc.manifest_sha'),'mapping_sha256',current_setting('plc.mapping_sha'),
      'mapping_token_sha256',current_setting('plc.mapping_token_sha'),'approvals_sha256',current_setting('plc.approvals_sha'),
      'go',current_setting('plc.go'),'decided_by_name',v_navn)
      ||CASE WHEN r.human IS NULL THEN '{}'::jsonb
             ELSE jsonb_build_object('human_header_levels',r.human,'human_review',r.review) END
      ||coalesce(r.rev,'{}'::jsonb);
    UPDATE plc_rec SET rp=private.write_record_placement(r.record_id, r.entry_id, v_vals, (v_ids->>'linje')::uuid, v_ev)
     WHERE record_key=r.record_key;
  END LOOP;
  UPDATE plc_rec SET pp=private.write_persona_placement(persona_id, rp, helpost,
    jsonb_build_object('rule_version','placement-membership-v1','record_placement_id',rp,'go',current_setting('plc.go'),
      'manifest_sha256',current_setting('plc.manifest_sha'),'decided_by_name',v_navn))
   WHERE persona;
  IF private.placement_header_violations(v_src)<>0 THEN RAISE EXCEPTION 'PLC_WRITE_NEAREST'; END IF;
  -- Ledger for kildens legacy-rækker (andre kilders rækker røres ikke).
  PERFORM private.record_legacy_disposition(l.person_id, v_src, l.disposition, f.rp,
            jsonb_build_object('rule_version','placement-membership-v1','go',current_setting('plc.go'),
              'manifest_sha256',current_setting('plc.manifest_sha'),'decided_by_name',v_navn)
            ||CASE WHEN l.grund IS NULL THEN '{}'::jsonb ELSE jsonb_build_object('grund',l.grund) END)
    FROM plc_ledger l LEFT JOIN plc_rec f ON f.record_key=l.record_key
   ORDER BY l.person_id;
END $skriv$;
-- Planner-statistik: tabellerne voksede i denne transaktion (memory restore-uden-planner-statistik).
ANALYZE private.source_record_occurrence, private.source_observation, private.extraction_run,
  private.source_record_placement, private.source_record_placement_decision, private.source_persona_placement,
  private.source_persona_placement_decision, private.legacy_placement_disposition, public.lineage_scheme_entry,
  public.lineage_scheme_entry_lineage;

-- Skrivning 3: medlemskaber gennem promotions-RPC'en (eget change_set), som redaktør.
SET LOCAL ROLE authenticated;
SELECT public.red_preview_placement_memberships(:src)::text AS g_pv \gset
RESET ROLE;
SELECT set_config('plc.pv', :'g_pv', true) \g /dev/null
DO $mid$
DECLARE v jsonb:=current_setting('plc.pv')::jsonb; e jsonb:=current_setting('plc.expect')::jsonb;
BEGIN
  -- Alle kildens items er egnede (persona-placements skrives kun med accepteret identitet, og PRE udelukkede overlap).
  IF (SELECT count(*) FROM jsonb_array_elements(v->'items') i WHERE (i->>'eligible')::boolean)<>(e->>'memberships')::bigint
     OR EXISTS (SELECT 1 FROM jsonb_array_elements(v->'items') i WHERE NOT (i->>'eligible')::boolean)
     OR btrim(coalesce(current_setting('app.change_set_id',true),''))<>'' THEN
    RAISE EXCEPTION 'PLC_MID_MEMBERSHIP_PREVIEW';
  END IF;
END $mid$;
SET LOCAL ROLE authenticated;
SELECT public.red_promote_placement_memberships(:src, :'g_pv'::jsonb->>'preview_sha256') AS g_promoted \gset
RESET ROLE;
DO $mid2$ BEGIN
  IF btrim(coalesce(current_setting('app.change_set_id',true),''))<>'' THEN RAISE EXCEPTION 'PLC_MID_GUC'; END IF;
END $mid2$;
ANALYZE public.person_lineage_membership, public.person_slaegt_membership, public.change_set, public.change_event;

-- Skrivning 4: revalidering. Én klientdrevet sætning pr. forældet publicering, slået op via recorden;
-- app.change_set_id ryddes før hvert kald. Tilstands-sha'en læses som ejer, sætningerne køres som redaktør.
CREATE TEMP TABLE plc_reval ON COMMIT DROP AS
SELECT row_number() OVER (ORDER BY b.record_key COLLATE "C", b.binding_id) AS ord, b.binding_id,
       format('SELECT set_config(%L,%L,true), public.red_revalider_person_narrative_record(%s,%s,%L,%L)',
              'app.change_set_id', '', b.person_id, :src, b.record_key, s->>'state_sha256') AS stmt
  FROM plc_binding b, LATERAL private.narrative_record_state(b.person_id, :src, b.record_key) s
 WHERE s->>'publication_status'='stale_published';
GRANT SELECT ON plc_reval TO authenticated;
SELECT count(*) AS g_reval FROM plc_reval \gset
SET LOCAL ROLE authenticated;
\o /dev/null
SELECT stmt FROM plc_reval ORDER BY ord \gexec
\o
RESET ROLE;
ANALYZE private.narrative_publication_event, private.narrative_record_publication, public.change_set, public.change_event;
SELECT set_config('app.change_set_id','',true), set_config('plc.reval', :'g_reval', true),
       set_config('plc.promoted', :'g_promoted', true) \g /dev/null
SELECT pg_temp.plc_paritet('efter') \g /dev/null

DO $post$
DECLARE v_src bigint:=current_setting('plc.src')::bigint; e jsonb:=current_setting('plc.expect')::jsonb; v_n bigint;
BEGIN
  IF btrim(coalesce(current_setting('app.change_set_id',true),''))<>'' THEN RAISE EXCEPTION 'PLC_POST_GUC'; END IF;
  -- Revalideret = præcis de publicerede bindinger på records, der fik placement (som mængde, ikke kun antal: hver af
  -- dem blev stale og revalideret, og ingen andre).
  IF current_setting('plc.reval')::bigint<>(e->>'revalidated')::bigint
     OR EXISTS ((SELECT binding_id FROM plc_reval)
                EXCEPT (SELECT b.binding_id FROM plc_binding b JOIN plc_rec f ON f.record_id=b.record_id
                         WHERE b.status='published' AND f.skriv))
     OR EXISTS ((SELECT b.binding_id FROM plc_binding b JOIN plc_rec f ON f.record_id=b.record_id
                  WHERE b.status='published' AND f.skriv)
                EXCEPT (SELECT binding_id FROM plc_reval)) THEN
    RAISE EXCEPTION 'PLC_POST_REVALIDATED n=%', current_setting('plc.reval');
  END IF;
  -- Publiceringer: samme publicerede, ingen forældede, uændret eligibility pr. binding, ingen nye blokeringer.
  CREATE TEMP TABLE plc_efter ON COMMIT DROP AS
  SELECT b.binding_id, s->>'publication_status' AS status, s->>'eligibility_status' AS eligibility,
         (s->>'blocking_reason') IS NOT NULL AS blocked
    FROM plc_binding b, LATERAL private.narrative_record_state(b.person_id, v_src, b.record_key) s;
  IF (SELECT count(*) FROM plc_efter WHERE status='published')<>(e->>'published')::bigint
     OR EXISTS (SELECT 1 FROM plc_efter WHERE status='stale_published') THEN
    RAISE EXCEPTION 'PLC_POST_PUBLISHED';
  END IF;
  IF EXISTS (SELECT 1 FROM plc_binding f JOIN plc_efter x USING (binding_id)
              WHERE f.status IS DISTINCT FROM x.status OR f.eligibility IS DISTINCT FROM x.eligibility
                 OR (x.blocked AND NOT f.blocked)) THEN
    RAISE EXCEPTION 'PLC_POST_ELIGIBILITY';
  END IF;
  -- Ledger: hver legacy-række i kilden har præcis den planlagte, gældende disposition. En ny version (højst én) bærer
  -- planens grund og, for mapped, ceremoniens placement; en uændret række (samme disposition som før, fx 5c-1's
  -- retained_legacy) får ingen ny version og beholder sin evidens.
  SELECT count(*) INTO v_n FROM private.legacy_placement_disposition_current WHERE source_id=v_src AND is_current;
  IF v_n<>(SELECT count(*) FROM public.person_external_id WHERE source_id=v_src)
     OR (SELECT count(*) FROM private.legacy_placement_disposition_current WHERE source_id=v_src AND disposition='mapped')
          <>(e->>'ledger_mapped')::bigint
     OR (SELECT count(*) FROM private.legacy_placement_disposition_current WHERE source_id=v_src AND disposition='retained_legacy')
          <>(e->>'ledger_retained')::bigint
     OR EXISTS (SELECT 1 FROM plc_ledger l LEFT JOIN private.legacy_placement_disposition_current d
                  ON d.person_id=l.person_id AND d.source_id=v_src
                 WHERE d.person_id IS NULL OR NOT d.is_current OR d.disposition IS DISTINCT FROM l.disposition
                    OR d.version>coalesce(l.foer_version,0)+1
                    OR (d.version=coalesce(l.foer_version,0) AND d.disposition IS DISTINCT FROM l.foer_disposition)
                    OR (d.version>coalesce(l.foer_version,0) AND d.evidence->>'grund' IS DISTINCT FROM l.grund)
                    OR (l.disposition='mapped' AND d.placement_id IS DISTINCT FROM
                          (SELECT f.rp FROM plc_rec f WHERE f.record_key=l.record_key))) THEN
    RAISE EXCEPTION 'PLC_POST_LEDGER n=%', v_n;
  END IF;
  -- Medlemskaber: ét pr. persona-placement, alle gældende, i begge tabeller.
  IF current_setting('plc.promoted')::bigint<>(e->>'memberships')::bigint
     OR (SELECT count(*) FROM public.person_lineage_membership WHERE source_basis->>'source_id'=v_src::text)
          <>(e->>'memberships')::bigint
     OR (SELECT count(*) FROM public.person_slaegt_membership WHERE source_basis->>'source_id'=v_src::text)
          <>(e->>'memberships')::bigint
     OR private.placement_membership_not_current()<>0 THEN
    RAISE EXCEPTION 'PLC_POST_MEMBERSHIPS';
  END IF;
  IF private.placement_header_violations(v_src)<>0 THEN RAISE EXCEPTION 'PLC_POST_NEAREST'; END IF;
  IF private.placement_human_header_levels(v_src)<>(e->>'human')::bigint THEN
    RAISE EXCEPTION 'PLC_POST_HUMAN_LEVELS n=%', private.placement_human_header_levels(v_src);
  END IF;
  -- Linjerækkefølgen: hver af kildens entries har mappingens sort_order (og ingen entry står uden for mappingen).
  IF EXISTS (SELECT 1 FROM public.lineage_scheme s JOIN public.lineage_scheme_entry le ON le.scheme_id=s.id
               LEFT JOIN plc_entry x ON x.code=le.code AND NOT x.parkeret
              WHERE s.source_id=v_src AND s.kind='stamtavle' AND le.sort_order IS DISTINCT FROM x.sort_order) THEN
    RAISE EXCEPTION 'PLC_POST_SORT_ORDER';
  END IF;
  -- Komponenttilstande i hele basen (konflikter skrives eller slettes aldrig af ceremonien).
  IF (SELECT count(*) FROM private.membership_component_states() WHERE state='corroborated')<>(e->>'corroborated')::bigint
     OR (SELECT count(*) FROM private.membership_component_states() WHERE state='conflict')<>(e->>'conflict')::bigint THEN
    RAISE EXCEPTION 'PLC_POST_COMPONENTS corroborated=% conflict=%',
      (SELECT count(*) FROM private.membership_component_states() WHERE state='corroborated'),
      (SELECT count(*) FROM private.membership_component_states() WHERE state='conflict');
  END IF;
  -- Paritet: læserne og andre kilders data er byte-identiske før og efter (koord_kilde afgøres af PLC_POST_LAESER).
  IF (SELECT count(*) FROM plc_paritet)<>11
     OR EXISTS (SELECT 1 FROM plc_paritet WHERE laeser<>'koord_kilde' AND (foer IS DISTINCT FROM efter OR foer IS NULL)) THEN
    RAISE EXCEPTION 'PLC_POST_PARITET %', (SELECT string_agg(laeser, ',' ORDER BY laeser) FROM plc_paritet
                                           WHERE laeser<>'koord_kilde' AND (foer IS DISTINCT FROM efter OR foer IS NULL));
  END IF;
  -- Andre kilders koordinater = baselinen fra maal_trin6d1.sql i fasen foer (før DDL'en).
  IF (SELECT efter FROM plc_paritet WHERE laeser='koord_andre') IS DISTINCT FROM e->>'koord' THEN
    RAISE EXCEPTION 'PLC_POST_KOORD';
  END IF;
  -- Kildens læserrækker: uaendret → samme hash før og efter; placement → hver kildes række for en person med et
  -- gældende medlemskab fra kilden viser placement (og mindst én gør).
  IF e->>'laeser'='uaendret' THEN
    IF (SELECT foer IS DISTINCT FROM efter FROM plc_paritet WHERE laeser='koord_kilde') THEN
      RAISE EXCEPTION 'PLC_POST_LAESER uaendret';
    END IF;
  ELSIF NOT EXISTS (SELECT 1 FROM public.public_person_source_coordinates() c
                     WHERE c.source_id=v_src AND c.provenance_kind='placement')
        OR EXISTS (SELECT 1 FROM public.public_person_source_coordinates() c
                    JOIN public.person_lineage_membership l ON l.person_id=c.person_id
                     AND l.source_basis->>'source_id'=v_src::text AND private.membership_is_current(l.person_id,l.lineage_id)
                   WHERE c.source_id=v_src AND c.provenance_kind<>'placement'
                     AND public.entitet_offentlig('person',c.person_id)) THEN
    RAISE EXCEPTION 'PLC_POST_LAESER placement';
  END IF;
END $post$;
COMMIT;
SELECT count(*) AS g_entries FROM public.lineage_scheme s JOIN public.lineage_scheme_entry e ON e.scheme_id=s.id
 WHERE s.source_id=:src AND s.kind='stamtavle' \gset
SELECT count(*) AS g_headers FROM private.source_observation o JOIN private.extraction_run r ON r.id=o.extraction_run_id
 WHERE r.source_id=:src AND r.run_key=:'header_rule_version' \gset
SELECT count(*) AS g_placements FROM private.source_record_placement rp JOIN private.source_record r ON r.id=rp.source_record_id
 WHERE r.source_id=:src \gset
SELECT count(*) AS g_persona FROM private.source_persona_placement pp JOIN private.source_record_placement rp ON rp.id=pp.record_placement_id
  JOIN private.source_record r ON r.id=rp.source_record_id WHERE r.source_id=:src \gset
SELECT count(*) AS g_mapped FROM private.legacy_placement_disposition_current WHERE source_id=:src AND disposition='mapped' \gset
SELECT private.placement_human_header_levels(:src) AS g_human \gset
SELECT count(*) FILTER (WHERE state='corroborated') AS g_cor, count(*) FILTER (WHERE state='conflict') AS g_con
  FROM private.membership_component_states() \gset
\echo PLC_OK entries=:g_entries headers=:g_headers placements=:g_placements persona=:g_persona ledger_mapped=:g_mapped memberships=:g_promoted revalideret=:g_reval corroborated=:g_cor conflict=:g_con human_levels=:g_human
