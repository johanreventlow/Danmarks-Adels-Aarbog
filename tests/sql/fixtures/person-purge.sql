-- Fuld personsletning, fixtur (Task 2a: kerne, familier og historik; Task 2b tilføjer ledgers og identitet).
-- KUN engangsbaser (tests/sql/test-person-purge.sh). Alle navne er syntetiske; ingen PII.
--
-- Personer (purge_test.ids, alle id > 1.000.000, så restsøgningens tal-token ikke forurenes; R10):
--   P              »Testperson Purge«, personen der skal slettes
--   aegtefaelle    familie fam_del med P og uden børn  → familien slettes (Fam_del)
--   anden_partner  familie fam_keep med P og barn       → familien bevares med vielse (Fam_keep)
--   barn           barn i fam_keep
--   nabo           én samme_som-nabo (grad 1, blokerer ikke)
--   tredje         uden forbindelse; har en note, hvis foer-tekst linker til P (Task 9)
--
-- Byggeregler:
--   * Personer, fakta, relationer, familier, narrativer, stories, feed-pins, medier, forslag og OCR-rettelsen skrives
--     af de rigtige red_*-skrivere. begin_change_set genbruger et åbent sæt i hele transaktionen
--     (app.change_set_id er transaktionslokal), så purge_test.nyt() nulstiller sættet før HVER skriver.
--   * Steder uden red_*-skriver i schema.sql skrives med direkte INSERT/UPDATE (forælder før barn), under et åbent
--     sæt når tabellen er versioneret: note, haendelse (ingen historik, som load_haendelser.R), entity_description,
--     bookmark (som klienten, via RLS), profiles-bindingen, person_external_id, medlemskaber, slægt/linjer/kilder.
--   * Historik kommer så vidt muligt fra skriverne eller fra rigtig DML under et åbent sæt (log_change skriver eventet).
--     Kun fortryd-sættene og de tidligere slettede rækker indsættes direkte i change_set/change_event; foer/row_pk
--     bygges med jsonb_populate_record/_row_pk, så formen er log_change's. withdraw-sættet åbnes med begin_change_set
--     uden DML (som withdraw_legacy_narrative, der kun skriver ikke-versionerede publiceringsrækker).
--   * purge_test.forventet (V2-2) fyldes trinvis ud fra de id'er, skriverne returnerede, og de sæt, de lige åbnede —
--     aldrig fra en forespørgsel af typen »alle rækker om P«. pk har version_pk_registry's form (som change_event.row_pk).
--
-- Kendte huller, der hører til Task 2b (ledgers/bogens lag): S9 (kvitteringen forbruges), S10-S12 (identitet),
-- S22-S24 (publicering), S33b (entity_description_source kræver source_record), S36 (red_ret_paastand kræver en
-- proposed/accepted interpretation for faktaets person via accepteret identitet), S39-S51. Det fælles sæt (rolle
-- faelles_saet) får sin narrative_publication_event-FK i 2b (R3).
\set ON_ERROR_STOP on
SELECT set_config('request.jwt.claim.sub','a2a00000-0000-4000-8000-00000000a001',false) \g /dev/null

BEGIN;

-- ---------------------------------------------------------------------------------------------------------------------
-- Testskema og hjælpere.
CREATE SCHEMA purge_test;
CREATE TABLE purge_test.ids(rolle text PRIMARY KEY, id bigint NOT NULL);
CREATE TABLE purge_test.forventet(
  tabel text NOT NULL, pk jsonb NOT NULL,
  handling text NOT NULL CHECK (handling IN ('slet','nulstil','loesn')),
  PRIMARY KEY (tabel, pk));
COMMENT ON TABLE purge_test.forventet IS
  'Facit (V2-2): rækker sletningen skal slette/nulstille/løsne. tabel uden skema = public.';

CREATE FUNCTION purge_test.id(p_rolle text) RETURNS bigint LANGUAGE plpgsql STABLE AS $$
DECLARE v bigint;
BEGIN
  SELECT id INTO v FROM purge_test.ids WHERE rolle=p_rolle;
  IF v IS NULL THEN RAISE EXCEPTION 'PURGE_FIXTURE: ukendt rolle %', p_rolle; END IF;
  RETURN v;
END $$;
CREATE FUNCTION purge_test.gem(p_rolle text, p_id bigint) RETURNS bigint LANGUAGE sql AS $$
  INSERT INTO purge_test.ids(rolle,id) VALUES (p_rolle,p_id) RETURNING id;
$$;
-- Nulstil det transaktionslokale sæt, så næste skriver åbner sit eget (begin_change_set l. 9344-9347).
CREATE FUNCTION purge_test.nyt() RETURNS void LANGUAGE sql AS $$
  SELECT set_config('app.change_set_id','',true), set_config('app.change_seq','',true);
$$;
-- Sættet, den seneste skriver åbnede.
CREATE FUNCTION purge_test.saet() RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v text := current_setting('app.change_set_id',true);
BEGIN
  IF v IS NULL OR v='' THEN RAISE EXCEPTION 'PURGE_FIXTURE: intet åbent change_set'; END IF;
  RETURN v::bigint;
END $$;
CREATE FUNCTION purge_test.f(p_tabel text, p_pk jsonb, p_handling text DEFAULT 'slet') RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO purge_test.forventet(tabel,pk,handling) VALUES (p_tabel,p_pk,p_handling)
  ON CONFLICT (tabel,pk) DO NOTHING;
  IF (SELECT handling FROM purge_test.forventet WHERE tabel=p_tabel AND pk=p_pk) <> p_handling THEN
    RAISE EXCEPTION 'PURGE_FIXTURE: % % har to handlinger', p_tabel, p_pk;
  END IF;
END $$;
-- Et sæt, der i sin helhed handler om P: sættet, alle dets events og (p_raekker) alle rækker, det indsatte, slettes.
CREATE FUNCTION purge_test.f_saet_helt(p_cs bigint, p_raekker boolean DEFAULT true) RETURNS void LANGUAGE plpgsql AS $$
DECLARE e record; n int := 0;
BEGIN
  FOR e IN SELECT id, tabel, row_pk, op FROM public.change_event WHERE change_set_id=p_cs ORDER BY seq LOOP
    PERFORM purge_test.f('change_event', jsonb_build_object('id',e.id));
    IF e.op='INSERT' AND p_raekker THEN PERFORM purge_test.f(e.tabel, e.row_pk); END IF;
    n := n+1;
  END LOOP;
  PERFORM purge_test.f('change_set', jsonb_build_object('id',p_cs));
END $$;
-- Ét event i et blandet sæt (sættet bevares, fordi andres events står tilbage).
CREATE FUNCTION purge_test.f_event(p_cs bigint, p_tabel text, p_row_pk jsonb) RETURNS void LANGUAGE plpgsql AS $$
DECLARE e record; n int := 0;
BEGIN
  FOR e IN SELECT id FROM public.change_event WHERE change_set_id=p_cs AND tabel=p_tabel AND row_pk=p_row_pk LOOP
    PERFORM purge_test.f('change_event', jsonb_build_object('id',e.id)); n := n+1;
  END LOOP;
  IF n=0 THEN RAISE EXCEPTION 'PURGE_FIXTURE: intet %-event % i sæt %', p_tabel, p_row_pk, p_cs; END IF;
END $$;
-- Fabrikeret historisk event; foer/efter får log_change's fulde rækkeform.
CREATE FUNCTION purge_test.hist_event(p_cs bigint, p_seq int, p_tabel text, p_op text, p_foer jsonb, p_efter jsonb)
RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v bigint;
BEGIN
  INSERT INTO public.change_event(change_set_id,seq,tabel,row_pk,op,foer,efter)
  VALUES (p_cs,p_seq,p_tabel,public._row_pk(p_tabel,coalesce(p_efter,p_foer)),p_op,p_foer,p_efter)
  RETURNING id INTO v;
  RETURN v;
END $$;
-- Fabrikeret fortryd-sæt, i samme form som red_fortryd_change_set (l. 9566-9573).
CREATE FUNCTION purge_test.fortryd_saet(p_orig bigint) RETURNS bigint LANGUAGE plpgsql AS $$
DECLARE v bigint;
BEGIN
  INSERT INTO public.change_set(actor_id,actor_navn,actor_rolle,operation,summary,
                                subjekt_type,subjekt_id,subjekt_synlighed,reverterer_id)
  SELECT auth.uid(),'Purge-redaktør','redaktion','fortryd',format('Fortrød: %s',coalesce(o.summary,'(uden tekst)')),
         o.subjekt_type,o.subjekt_id,o.subjekt_synlighed,o.id
    FROM public.change_set o WHERE o.id=p_orig
  RETURNING id INTO v;
  IF v IS NULL THEN RAISE EXCEPTION 'PURGE_FIXTURE: sæt % findes ikke', p_orig; END IF;
  RETURN v;
END $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Sekvenser (R10): personer fra 1.500.001; alle andre public-sekvenser i hver sit interval fra 10.000.000, så intet
-- andet id kan blive lig P's id. Fabrikerede, tidligere slettede rækker tager senere deres id med nextval.
DO $$
DECLARE r record; k int := 0;
BEGIN
  FOR r IN SELECT c.oid::regclass AS seq FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE c.relkind='S' AND n.nspname='public' ORDER BY c.relname LOOP
    k := k+1;
    PERFORM setval(r.seq, CASE WHEN r.seq=pg_get_serial_sequence('public.person','id')::regclass
                               THEN 1500000 ELSE 10000000 + k*1000000 END, true);
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Redaktør, kilder, slægt, linjer, ejendom og organisation (opsætning, ikke P's spor; ingen historik).
INSERT INTO auth.users(id,email) VALUES
  ('a2a00000-0000-4000-8000-00000000a001','purge-redaktoer@test.invalid'),
  ('a2a00000-0000-4000-8000-00000000b001','purge-medlem@test.invalid');
INSERT INTO public.profiles(id,rolle,navn,email) VALUES
  ('a2a00000-0000-4000-8000-00000000a001','redaktion','Purge-redaktør','purge-redaktoer@test.invalid'),
  ('a2a00000-0000-4000-8000-00000000b001','medlem','Bundet medlem','purge-medlem@test.invalid');


DO $$
DECLARE v_sa bigint; v_sb bigint; v_sl bigint; v_la bigint; v_lb bigint; v_est bigint; v_org bigint;
BEGIN
  INSERT INTO public.source(slags,titel,udgave,aar,import_key)
    VALUES ('DAA-udgave','Purgekilde A','Syntetisk',1939,'purge-test:kilde-a') RETURNING id INTO v_sa;
  INSERT INTO public.source(slags,titel,udgave,aar) VALUES ('bog','Purgekilde B','Syntetisk',1950) RETURNING id INTO v_sb;
  INSERT INTO public.slaegt(navn,sorteringsnavn,slug) VALUES ('Purgeslægt','Purgeslægt','purgeslaegt') RETURNING id INTO v_sl;
  -- To linjer med hvert sit slægtsnavn: P's to external-id'er giver n_distinct=2 → slaegtsnavn_karantaene (S4).
  INSERT INTO public.lineage(source_id,kode,navn,slaegtsnavn,slaegt_id)
    VALUES (v_sa,'A','Purgelinje A','Purgeslægt',v_sl) RETURNING id INTO v_la;
  INSERT INTO public.lineage(source_id,kode,navn,slaegtsnavn)
    VALUES (v_sb,'B','Prøvelinje B','Prøveslægt') RETURNING id INTO v_lb;
  PERFORM purge_test.gem('kilde_a',v_sa); PERFORM purge_test.gem('kilde_b',v_sb);
  PERFORM purge_test.gem('slaegt',v_sl); PERFORM purge_test.gem('linje_a',v_la); PERFORM purge_test.gem('linje_b',v_lb);
  PERFORM purge_test.nyt(); v_est := public.red_opret_estate('Purgegaard','gods');
  PERFORM purge_test.nyt(); v_org := public.red_opret_organisation('Purgeordenen','orden');
  PERFORM purge_test.gem('ejendom',v_est); PERFORM purge_test.gem('organisation',v_org);
END $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Step 1: personerne (red_opret_person). P's oprettelsessæt har summary 'Oprettede person Testperson Purge' og kun
-- P's events (person + navn/fødsel/død/titel med påstand, citat og konklusion) → slettes helt.
DO $$
DECLARE v bigint; r record;
BEGIN
  PERFORM purge_test.nyt();
  v := public.red_opret_person('Testperson Purge','mand',false,'1850','1920','Kammerherre');
  PERFORM purge_test.gem('P',v);
  PERFORM purge_test.gem('saet_opret_P',purge_test.saet());
  PERFORM purge_test.f_saet_helt(purge_test.saet());
  FOR r IN SELECT * FROM (VALUES ('aegtefaelle','Testperson Ægtefælle','kvinde'),('anden_partner','Testperson Anden','kvinde'),
                                 ('barn','Testperson Barn','mand'),('nabo','Testperson Nabo','mand'),
                                 ('tredje','Testperson Tredje','kvinde')) x(rolle,navn,koen) LOOP
    PERFORM purge_test.nyt();
    PERFORM purge_test.gem(r.rolle, public.red_opret_person(r.navn,r.koen,false,'1855',NULL,NULL));
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Familier.
--   fam_del  = union(P, aegtefaelle), ingen børn → Fam_del. Sættet (subjekt P) har også ægtefællens events; de
--              hører alle til den slettede familie → sættet slettes helt.
--   fam_keep = union(P, anden_partner) + barn → Fam_keep. Sættet (subjekt P) bevares; kun P's family_member-event går.
DO $$
DECLARE v_p bigint := purge_test.id('P'); v_del bigint; v_keep bigint; v_cs bigint; v_pk jsonb;
BEGIN
  PERFORM purge_test.nyt();
  v_del := public.red_opret_union(v_p, purge_test.id('aegtefaelle'), 'vielse', 1);
  PERFORM purge_test.gem('fam_del',v_del); PERFORM purge_test.gem('saet_union_del',purge_test.saet());
  PERFORM purge_test.f_saet_helt(purge_test.saet());

  PERFORM purge_test.nyt();
  v_keep := public.red_opret_union(v_p, purge_test.id('anden_partner'), 'vielse', 2);
  v_cs := purge_test.saet();
  PERFORM purge_test.gem('fam_keep',v_keep); PERFORM purge_test.gem('saet_union_keep',v_cs);
  v_pk := jsonb_build_object('family_id',v_keep,'person_id',v_p,'rolle','partner');
  PERFORM purge_test.f_event(v_cs,'family_member',v_pk);
  PERFORM purge_test.f('family_member',v_pk);

  PERFORM purge_test.nyt();
  PERFORM public.red_tilfoej_barn(v_keep, purge_test.id('barn'));
END $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- P's fakta, påstande, citater og konklusioner (ud over oprettelsens fire).
DO $$
DECLARE v_p bigint := purge_test.id('P'); v_titel bigint; j jsonb;
BEGIN
  SELECT id INTO v_titel FROM public.fact WHERE subjekt_type='person' AND subjekt_id=v_p AND faktatype='titel';
  PERFORM purge_test.gem('fakta_titel',v_titel);
  -- Ny påstand + citat på titlen (ikke valgt som konklusion).
  PERFORM purge_test.nyt();
  j := public.red_tilfoej_oplysning(v_titel,'Hofjægermester',p_kilde_fritekst=>'Syntetisk kilde, s. 2');
  PERFORM purge_test.gem('assertion_titel_2',(j->>'assertion_id')::bigint);
  PERFORM purge_test.f_saet_helt(purge_test.saet());
  -- Endnu et faktum (erhverv); bruges som anker for andres hændelse/story (S27/S31).
  PERFORM purge_test.nyt();
  j := public.red_opret_fakta('person',v_p,'erhverv','Godsejer',p_kilde_fritekst=>'Syntetisk kilde, s. 3');
  PERFORM purge_test.gem('fakta_erhverv',(j->>'fact_id')::bigint);
  PERFORM purge_test.f_saet_helt(purge_test.saet());
  -- Vielse på den slettede familie (F_fam) og på den bevarede (K5: citatet nævner P, bogtekst der bevares).
  PERFORM purge_test.nyt();
  j := public.red_opret_fakta('family',purge_test.id('fam_del'),'vielse','1875',p_date_raw=>'1875');
  PERFORM purge_test.gem('fakta_vielse_del',(j->>'fact_id')::bigint);
  PERFORM purge_test.f_saet_helt(purge_test.saet());
  PERFORM purge_test.nyt();
  j := public.red_opret_fakta('family',purge_test.id('fam_keep'),'vielse','1880',p_date_raw=>'1880',
                              p_kilde_fritekst=>'g. 1880 m. Testperson Purge');
  PERFORM purge_test.gem('fakta_vielse_keep',(j->>'fact_id')::bigint);
END $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Relationer: til en ejendom, med fact-ende (S19), samme_som-naboen (med påstand og konklusion), og en relation med
-- den slettede familie som ende (R_fam). Alle sæt handler kun om P/Fam_del → slettes helt.
DO $$
DECLARE v_p bigint := purge_test.id('P'); v bigint;
BEGIN
  PERFORM purge_test.nyt();
  v := public.red_tilfoej_relation(v_p,'estate',purge_test.id('ejendom'),'ejer','1880-1920');
  PERFORM purge_test.gem('relation_ejendom',v); PERFORM purge_test.f_saet_helt(purge_test.saet());

  PERFORM purge_test.nyt();
  v := public.red_relation('fact',purge_test.id('fakta_titel'),'organisation',purge_test.id('organisation'),'tildelt_af');
  PERFORM purge_test.gem('relation_fact_ende',v); PERFORM purge_test.f_saet_helt(purge_test.saet());

  PERFORM purge_test.nyt();
  v := public.red_samme_som(purge_test.id('nabo'),v_p);
  PERFORM purge_test.gem('relation_samme_som',v); PERFORM purge_test.f_saet_helt(purge_test.saet());

  PERFORM purge_test.nyt();
  v := public.red_relation('family',purge_test.id('fam_del'),'estate',purge_test.id('ejendom'),'ejer');
  PERFORM purge_test.gem('relation_fam_del',v); PERFORM purge_test.f_saet_helt(purge_test.saet());
END $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Medier. Eksklusivt: kun P er afbildet → mediet slettes (M_del), sættet slettes helt.
-- Delt: P og anden_partner er afbildet → mediet bevares. Upload-sættet bevarer medie-eventet og titlen (K3/Q8);
-- kun P's relation og dens event går.
DO $$
DECLARE v_p bigint := purge_test.id('P'); v bigint; v_cs bigint; v_rel bigint;
BEGIN
  PERFORM purge_test.nyt();
  v := public.red_upload_media('foto','Portræt af Testperson Purge','purge-test/eksklusiv.jpg','image/jpeg',
                               p_afbildet_person_id=>v_p);
  PERFORM purge_test.gem('medie_eksklusiv',v); PERFORM purge_test.f_saet_helt(purge_test.saet());

  PERFORM purge_test.nyt();
  v := public.red_upload_media('foto','Gruppeportræt med Testperson Purge','purge-test/delt.jpg','image/jpeg',
                               p_afbildet_person_id=>v_p);
  v_cs := purge_test.saet();
  PERFORM purge_test.gem('medie_delt',v); PERFORM purge_test.gem('saet_medie_delt',v_cs);
  SELECT id INTO v_rel FROM public.relation
   WHERE rolle='afbildet' AND subjekt_type='person' AND subjekt_id=v_p AND objekt_type='media' AND objekt_id=v;
  PERFORM purge_test.f_event(v_cs,'relation',jsonb_build_object('id',v_rel));
  PERFORM purge_test.f('relation',jsonb_build_object('id',v_rel));
  PERFORM purge_test.nyt();
  PERFORM public.red_relation('person',purge_test.id('anden_partner'),'media',v,'afbildet');
END $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Narrativer og hændelser. P's narrativ linker til anden_partner (text_mention med kilde i P's prosa, S28).
-- Hændelser har ingen skriver (load_haendelser.R indlæser uden sæt): H1 under P's narrativ (S25), H2 med P som
-- subjekt under anden_partners narrativ (S26), H3 er anden_partners, forankret i P's fakta og relation (S27 loesn).
DO $$
DECLARE v_p bigint := purge_test.id('P'); v_a bigint := purge_test.id('anden_partner'); v_np bigint; v_na bigint;
        v_nf bigint; v bigint;
BEGIN
  PERFORM purge_test.nyt();
  v_np := public.red_upsert_narrativ('person',v_p,
    format('Testperson Purge var kammerherre og gift med [[person:%s|Testperson Anden]].',v_a),false,purge_test.id('kilde_b'),'12');
  PERFORM purge_test.gem('narrativ_P',v_np); PERFORM purge_test.f_saet_helt(purge_test.saet());
  PERFORM purge_test.f('text_mention',jsonb_build_object('kilde_type','narrative','kilde_id',v_np,'maal_type','person','maal_id',v_a));

  PERFORM purge_test.nyt();
  v_nf := public.red_upsert_narrativ('family',purge_test.id('fam_del'),'Om ægteskabet, der blev opløst.',false,
                                     purge_test.id('kilde_b'),'13');
  PERFORM purge_test.gem('narrativ_fam_del',v_nf); PERFORM purge_test.f_saet_helt(purge_test.saet());

  PERFORM purge_test.nyt();
  v_na := public.red_upsert_narrativ('person',v_a,'Testperson Anden levede på landet.',false,purge_test.id('kilde_b'),'14');
  PERFORM purge_test.gem('narrativ_anden',v_na);

  PERFORM purge_test.nyt();  -- hændelserne indlæses uden sæt (som load_haendelser.R)
  INSERT INTO public.haendelse(subjekt_type,subjekt_id,narrative_id,noegle,klausul,kategori,date_raw)
    VALUES ('person',v_p,v_np,'purge-h1','udnævnt til kammerherre 1890','embede','1890') RETURNING id INTO v;
  PERFORM purge_test.gem('haendelse_P',v); PERFORM purge_test.f('haendelse',jsonb_build_object('id',v));
  INSERT INTO public.haendelse(subjekt_type,subjekt_id,narrative_id,noegle,klausul,kategori,date_raw)
    VALUES ('person',v_p,v_na,'purge-h2','blev gift 1880','vielse','1880') RETURNING id INTO v;
  PERFORM purge_test.gem('haendelse_P_hos_anden',v); PERFORM purge_test.f('haendelse',jsonb_build_object('id',v));
  INSERT INTO public.haendelse(subjekt_type,subjekt_id,narrative_id,noegle,klausul,kategori,date_raw,fact_id,relation_id)
    VALUES ('person',v_a,v_na,'purge-h3','flyttede til godset 1881','bolig','1881',
            purge_test.id('fakta_erhverv'),purge_test.id('relation_ejendom')) RETURNING id INTO v;
  PERFORM purge_test.gem('haendelse_anden_forankret',v); PERFORM purge_test.f('haendelse',jsonb_build_object('id',v),'loesn');
END $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Stories: P's story med kildeliste (story_kilde), en story på den slettede familie, og anden_partners story
-- forankret i P's fakta, relation og hændelse (S31, ON DELETE SET NULL → loesn).
DO $$
DECLARE v_p bigint := purge_test.id('P'); v bigint;
BEGIN
  PERFORM purge_test.nyt();
  v := public.red_opret_story('person',v_p,'Testperson Purge red hver morgen.','Morgenridtet');
  PERFORM purge_test.gem('story_P',v); PERFORM purge_test.f_saet_helt(purge_test.saet());
  PERFORM purge_test.nyt();
  PERFORM public.red_set_story_kilder(v,jsonb_build_array(jsonb_build_object('source_id',purge_test.id('kilde_b'),'side','15')));
  PERFORM purge_test.f_saet_helt(purge_test.saet());

  PERFORM purge_test.nyt();
  v := public.red_opret_story('family',purge_test.id('fam_del'),'Brylluppet varede tre dage.','Brylluppet');
  PERFORM purge_test.gem('story_fam_del',v); PERFORM purge_test.f_saet_helt(purge_test.saet());

  PERFORM purge_test.nyt();
  v := public.red_opret_story('person',purge_test.id('anden_partner'),'Testperson Anden overtog godset.','Godset',
         p_haendelse_id=>purge_test.id('haendelse_P'),p_fact_id=>purge_test.id('fakta_erhverv'),
         p_relation_id=>purge_test.id('relation_ejendom'));
  PERFORM purge_test.gem('story_anden_forankret',v); PERFORM purge_test.f('story',jsonb_build_object('id',v),'loesn');
END $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Noter (ingen skriver; direkte INSERT under et åbent sæt): på P, på P's faktum, på P's relation og på den slettede
-- familie. Noten på P linker til barnet (text_mention med kilde i P's note, S28).
DO $$
DECLARE v_p bigint := purge_test.id('P'); v bigint;
BEGIN
  PERFORM purge_test.nyt();
  PERFORM public.begin_change_set('purge_test_noter',format('Noter på person %s',v_p),'person',v_p);
  INSERT INTO public.note(target_type,target_id,indhold)
    VALUES ('person',v_p,format('Far til [[person:%s|Testperson Barn]].',purge_test.id('barn'))) RETURNING id INTO v;
  PERFORM purge_test.gem('note_P',v);
  PERFORM purge_test.f('text_mention',jsonb_build_object('kilde_type','note','kilde_id',v,'maal_type','person','maal_id',purge_test.id('barn')));
  INSERT INTO public.note(target_type,target_id,indhold) VALUES ('fact',purge_test.id('fakta_titel'),'Titlen er usikker.');
  INSERT INTO public.note(target_type,target_id,indhold) VALUES ('relation',purge_test.id('relation_ejendom'),'Ejede godset i 40 år.');
  INSERT INTO public.note(target_type,target_id,indhold) VALUES ('family',purge_test.id('fam_del'),'Ægteskabet blev opløst.');
  PERFORM purge_test.f_saet_helt(purge_test.saet());
END $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Beskrivelse (entity_description; ingen skriver) og forslag (red_suggest, uden historik).
DO $$
DECLARE v_p bigint := purge_test.id('P'); v bigint;
BEGIN
  PERFORM purge_test.nyt();
  PERFORM public.begin_change_set('purge_test_beskrivelse',format('Beskrivelse af person %s',v_p),'person',v_p);
  INSERT INTO public.entity_description(subjekt_type,subjekt_id,kind,tekst,created_by)
    VALUES ('person',v_p,'overview','Testperson Purge var kammerherre.',auth.uid()) RETURNING id INTO v;
  PERFORM purge_test.gem('beskrivelse_P',v); PERFORM purge_test.f_saet_helt(purge_test.saet());

  PERFORM purge_test.nyt();
  v := public.red_suggest('rettelse','person',v_p,'titel','Overhofmester',NULL,'{}'::jsonb,'Forslag til P');
  PERFORM purge_test.gem('forslag_P',v); PERFORM purge_test.f('suggestion',jsonb_build_object('id',v));
  v := public.red_suggest('rettelse','family',purge_test.id('fam_del'),'vielse','1876',NULL,'{}'::jsonb,'Forslag til familien');
  PERFORM purge_test.gem('forslag_fam_del',v); PERFORM purge_test.f('suggestion',jsonb_build_object('id',v));
END $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Feed-pins i hvert nøgleformat (S32 + NY-B), via red_set_feed_pin; forbundet:<fam_keep> bevares (S32c).
DO $$
DECLARE v_p bigint := purge_test.id('P'); k text;
BEGIN
  FOREACH k IN ARRAY ARRAY[
    'portrait:'||v_p, 'citat:'||v_p, 'naevnt:'||v_p, 'dagensperson:'||v_p,
    'jubilaeum:'||v_p||':født:200', 'embede:'||v_p||':Kammerherre:1890',
    'slaegt:'||v_p||':'||purge_test.id('barn'), 'slaegt:'||purge_test.id('anden_partner')||':'||v_p,
    'arkiv:'||purge_test.id('haendelse_P'), 'paadennedag:h:'||purge_test.id('haendelse_P'),
    'story:'||purge_test.id('story_P'), 'forbundet:'||purge_test.id('fam_del')] LOOP
    PERFORM purge_test.nyt();
    PERFORM public.red_set_feed_pin(k,'pin');
    PERFORM purge_test.f_saet_helt(purge_test.saet());
  END LOOP;
  PERFORM purge_test.nyt();
  PERFORM public.red_set_feed_pin('forbundet:'||purge_test.id('fam_keep'),'pin');
END $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Bogmærke (som klienten: authenticated + RLS), profilbinding (versioneret: kun reventlow_person_id, l. 9184),
-- external-id'er, medlemskaber, slægtsnavnekarantæne og OCR-rettelse med import_korrektion.
DO $$
DECLARE v_p bigint := purge_test.id('P'); v_bm uuid; v_fp text;
BEGIN
  SET LOCAL ROLE authenticated;
  INSERT INTO public.bookmark(person_id) VALUES (v_p) RETURNING id INTO v_bm;
  RESET ROLE;
  PERFORM purge_test.f('bookmark',jsonb_build_object('id',v_bm));

  PERFORM purge_test.nyt();
  PERFORM public.begin_change_set('purge_test_profilbinding',format('Bandt profil til person %s',v_p),'person',v_p);
  UPDATE public.profiles SET reventlow_person_id=v_p WHERE id='a2a00000-0000-4000-8000-00000000b001';
  PERFORM purge_test.f_saet_helt(purge_test.saet());
  PERFORM purge_test.f('profiles',jsonb_build_object('id','a2a00000-0000-4000-8000-00000000b001'),'nulstil');

  -- External-id'er som indlæseren: én med record_key i kilde A (OCR-ankeret), én uden record_key i kilde B.
  PERFORM purge_test.nyt();
  PERFORM public.begin_change_set('purge_test_external_id',format('External-id for person %s',v_p),'person',v_p);
  INSERT INTO public.person_external_id(person_id,source_id,linje,nr,record_key)
    VALUES (v_p,purge_test.id('kilde_a'),'A',1,'PURGE-P');
  INSERT INTO public.person_external_id(person_id,source_id,linje,nr) VALUES (v_p,purge_test.id('kilde_b'),'B',7);
  PERFORM purge_test.f_saet_helt(purge_test.saet());
  IF NOT EXISTS (SELECT 1 FROM public.slaegtsnavn_karantaene WHERE person_id=v_p) THEN
    RAISE EXCEPTION 'PURGE_FIXTURE: regen lagde ikke P i slaegtsnavn_karantaene';
  END IF;
  PERFORM purge_test.f('slaegtsnavn_karantaene',jsonb_build_object('person_id',v_p));

  PERFORM purge_test.nyt();
  PERFORM public.begin_change_set('purge_test_medlemskab',format('Medlemskaber for person %s',v_p),'person',v_p);
  INSERT INTO public.person_slaegt_membership(person_id,slaegt_id,membership_kind)
    VALUES (v_p,purge_test.id('slaegt'),'editorial');
  INSERT INTO public.person_lineage_membership(person_id,lineage_id,role) VALUES (v_p,purge_test.id('linje_a'),'member');
  PERFORM purge_test.f_saet_helt(purge_test.saet());

  -- OCR-rettelse af køn (kræver ikke et citat med kilde): import_korrektion på (kilde A's import_key, PURGE-P).
  v_fp := private.ocr_fingerprint('purge-test:kilde-a','PURGE-P','koen',
            private.ocr_importeret('koen',(SELECT koen FROM public.person WHERE id=v_p),NULL,NULL,NULL,NULL,NULL,NULL),NULL);
  PERFORM purge_test.nyt();
  PERFORM public.red_ret_ocr_felt(v_p,'purge-test:kilde-a','PURGE-P','koen',v_fp,'{"value":"ukendt"}'::jsonb,'rettet');
  PERFORM purge_test.gem('saet_ocr',purge_test.saet());
  PERFORM purge_test.f_saet_helt(purge_test.saet());
END $$;

-- =====================================================================================================================
-- Step 2: historik.
DO $$
DECLARE v_p bigint := purge_test.id('P'); v_a bigint := purge_test.id('anden_partner'); v_cs bigint; v bigint; j jsonb;
        v_f bigint; v_ass bigint; v_cit bigint; v_rel bigint; v_nar bigint; v_note bigint;
BEGIN
  -- (1) Fortryd-sæt for P's oprettelse: slettes via Frev, fordi originalen slettes helt.
  v := purge_test.fortryd_saet(purge_test.id('saet_opret_P'));
  PERFORM purge_test.gem('saet_fortryd_opret_P',v); PERFORM purge_test.f('change_set',jsonb_build_object('id',v));
  -- (2) Fortryd-sæt for det bevarede union-sæt (subjekt P kopieret, reverterer_id sat): bevares (§2.4 punkt 2).
  v := purge_test.fortryd_saet(purge_test.id('saet_union_keep'));
  PERFORM purge_test.gem('saet_fortryd_bevaret',v);

  -- (3) Fælles sæt: P's og anden_partners fakta i ét sæt (subjekt anden_partner). P's rækker og events går; sættet
  --     bevares med anden_partners events. Task 2b tilføjer en narrative_publication_event, der peger på det (R3).
  PERFORM purge_test.nyt();
  v_cs := public.begin_change_set('purge_test_faelles',format('Fælles opdatering af person %s og %s',v_p,v_a),'person',v_a);
  PERFORM purge_test.gem('faelles_saet',v_cs);
  j := public.red_upsert_fakta('person',v_p,'bopæl','Purgegaard');
  PERFORM purge_test.gem('fakta_bopael_faelles',(j->>'fact_id')::bigint);
  PERFORM purge_test.f_event(v_cs,'fact',jsonb_build_object('id',(j->>'fact_id')::bigint));
  PERFORM purge_test.f_event(v_cs,'assertion',jsonb_build_object('id',(j->>'assertion_id')::bigint));
  PERFORM purge_test.f_event(v_cs,'citation',jsonb_build_object('id',(j->>'citation_id')::bigint));
  PERFORM purge_test.f_event(v_cs,'conclusion',jsonb_build_object('id',(j->>'conclusion_id')::bigint));
  PERFORM purge_test.f('fact',jsonb_build_object('id',(j->>'fact_id')::bigint));
  PERFORM purge_test.f('assertion',jsonb_build_object('id',(j->>'assertion_id')::bigint));
  PERFORM purge_test.f('citation',jsonb_build_object('id',(j->>'citation_id')::bigint));
  PERFORM purge_test.f('conclusion',jsonb_build_object('id',(j->>'conclusion_id')::bigint));
  PERFORM public.red_upsert_fakta('person',v_a,'bopæl','Andengaard');
  IF purge_test.saet() <> v_cs THEN RAISE EXCEPTION 'PURGE_FIXTURE: fælles sæt blev ikke genbrugt'; END IF;

  -- (4) Tilbagetrækning af et legacy-narrativ: subjekt P, fritekst med navnet, INGEN events (§2.4 punkt 2).
  PERFORM purge_test.nyt();
  v := public.begin_change_set('narrative_record_legacy_withdrawn',
         format('Tilbagetrak legacy-narrativ %s: %s','a2a00000-0000-4000-8000-0000000000c1',
                'trukket tilbage efter henvendelse om Testperson Purge'),'person',v_p);
  PERFORM purge_test.gem('saet_withdraw',v); PERFORM purge_test.f('change_set',jsonb_build_object('id',v));

  -- (5) Tidligere slettede rækker, der kun findes i change_event.foer: et faktum med påstand og citat, en relation og
  --     et narrativ. Id'erne tages fra de rigtige sekvenser, så ingen skriver senere kan få dem.
  v_f   := nextval(pg_get_serial_sequence('public.fact','id'));
  v_ass := nextval(pg_get_serial_sequence('public.assertion','id'));
  v_cit := nextval(pg_get_serial_sequence('public.citation','id'));
  v_rel := nextval(pg_get_serial_sequence('public.relation','id'));
  v_nar := nextval(pg_get_serial_sequence('public.narrative','id'));
  PERFORM purge_test.gem('hist_fakta',v_f); PERFORM purge_test.gem('hist_assertion',v_ass);
  PERFORM purge_test.gem('hist_citation',v_cit); PERFORM purge_test.gem('hist_relation',v_rel);
  PERFORM purge_test.gem('hist_narrativ',v_nar);
  PERFORM purge_test.nyt();
  v_cs := public.begin_change_set('purge_test_tidligere_slettet',format('Slettede ældre oplysninger på person %s',v_p),'person',v_p);
  PERFORM purge_test.gem('saet_tidligere_slettet',v_cs);
  PERFORM purge_test.hist_event(v_cs,1,'citation','DELETE',to_jsonb(jsonb_populate_record(NULL::public.citation,
    jsonb_build_object('id',v_cit,'assertion_id',v_ass,'citat_tekst','Kammerjunker 1875'))),NULL);
  PERFORM purge_test.hist_event(v_cs,2,'assertion','DELETE',to_jsonb(jsonb_populate_record(NULL::public.assertion,
    jsonb_build_object('id',v_ass,'target_type','fact','target_id',v_f,'vaerdi_tekst','Kammerjunker','uforanderlig',false))),NULL);
  PERFORM purge_test.hist_event(v_cs,3,'fact','DELETE',to_jsonb(jsonb_populate_record(NULL::public.fact,
    jsonb_build_object('id',v_f,'subjekt_type','person','subjekt_id',v_p,'faktatype','titel'))),NULL);
  PERFORM purge_test.hist_event(v_cs,4,'relation','DELETE',to_jsonb(jsonb_populate_record(NULL::public.relation,
    jsonb_build_object('id',v_rel,'subjekt_type','person','subjekt_id',v_p,'objekt_type','estate',
                       'objekt_id',purge_test.id('ejendom'),'rolle','forpagter'))),NULL);
  PERFORM purge_test.hist_event(v_cs,5,'narrative','DELETE',to_jsonb(jsonb_populate_record(NULL::public.narrative,
    jsonb_build_object('id',v_nar,'subjekt_type','person','subjekt_id',v_p,'source_id',purge_test.id('kilde_b'),
                       'tekst','Ældre biografi om Testperson Purge.','privat',false))),NULL);
  PERFORM purge_test.f_saet_helt(v_cs);

  -- (6) En note, hvis target flyttede væk fra P (rigtig UPDATE under sæt): begge events har P i foer/efter → slettes;
  --     noten selv er nu anden_partners og bevares.
  PERFORM purge_test.nyt();
  PERFORM public.begin_change_set('purge_test_note',format('Note på person %s',v_p),'person',v_p);
  INSERT INTO public.note(target_type,target_id,indhold) VALUES ('person',v_p,'Tilhørte måske den anden gren.')
    RETURNING id INTO v_note;
  PERFORM purge_test.gem('note_flyttet',v_note); PERFORM purge_test.gem('saet_note_oprettet',purge_test.saet());
  PERFORM purge_test.f('change_set',jsonb_build_object('id',purge_test.saet()));
  PERFORM purge_test.f_event(purge_test.saet(),'note',jsonb_build_object('id',v_note));
  PERFORM purge_test.nyt();
  PERFORM public.begin_change_set('purge_test_note_flyt',format('Flyttede note %s',v_note),NULL,NULL);
  UPDATE public.note SET target_id=v_a WHERE id=v_note;
  PERFORM purge_test.gem('saet_note_flyttet',purge_test.saet());
  PERFORM purge_test.f('change_set',jsonb_build_object('id',purge_test.saet()));
  PERFORM purge_test.f_event(purge_test.saet(),'note',jsonb_build_object('id',v_note));

  -- (7) En embede-pin, der er sat og fjernet igen: findes kun i historikken.
  PERFORM purge_test.nyt();
  PERFORM public.red_set_feed_pin('embede:'||v_p||':Hofjægermester:1900','pin');
  PERFORM purge_test.f_saet_helt(purge_test.saet(),false);
  PERFORM purge_test.nyt();
  PERFORM public.red_fjern_feed_pin('embede:'||v_p||':Hofjægermester:1900');
  PERFORM purge_test.f_saet_helt(purge_test.saet(),false);

  -- (8) tredjes note, hvis foer-tekst linkede til P (Task 9: fortryd må ikke genskabe et dødt link). Noten oprettes med
  --     linket og rettes derefter; den levende tekst har intet link til P (ellers blokerer S29). Bevares (K2).
  PERFORM purge_test.nyt();
  PERFORM public.begin_change_set('purge_test_note_tredje',format('Note på person %s',purge_test.id('tredje')),
                                  'person',purge_test.id('tredje'));
  INSERT INTO public.note(target_type,target_id,indhold)
    VALUES ('person',purge_test.id('tredje'),format('Se også [[person:%s|Testperson Purge]].',v_p)) RETURNING id INTO v_note;
  PERFORM purge_test.gem('note_tredje',v_note);
  PERFORM purge_test.nyt();
  PERFORM public.begin_change_set('purge_test_note_tredje_ret',format('Rettede note %s',v_note),'person',purge_test.id('tredje'));
  UPDATE public.note SET indhold='Se også arkivet.' WHERE id=v_note;
  PERFORM purge_test.gem('saet_note_tredje_link_i_foer',purge_test.saet());
  PERFORM purge_test.nyt();
END $$;

-- =====================================================================================================================
-- Kontrol af fixturen (fejler hårdt, så en defekt fixtur aldrig bliver grundlag for en test).
DO $$
DECLARE r record; n bigint; v_p bigint := purge_test.id('P');
BEGIN
  -- Personerne: seks, alle > 1.000.000 (R10), og P bærer navnet.
  IF (SELECT count(*) FROM purge_test.ids i JOIN public.person p ON p.id=i.id
       WHERE i.rolle IN ('P','aegtefaelle','barn','anden_partner','nabo','tredje') AND i.id > 1000000) <> 6 THEN
    RAISE EXCEPTION 'PURGE_FIXTURE_KONTROL: personroller';
  END IF;
  IF (SELECT visning_navn FROM public.person WHERE id=v_p) IS DISTINCT FROM 'Testperson Purge' THEN
    RAISE EXCEPTION 'PURGE_FIXTURE_KONTROL: P''s visningsnavn';
  END IF;
  -- Navnet må kun stå på P (ingen anden persons navn indeholder det).
  IF EXISTS (SELECT 1 FROM public.person WHERE id<>v_p AND visning_navn LIKE '%Testperson Purge%') THEN
    RAISE EXCEPTION 'PURGE_FIXTURE_KONTROL: navnet står på en anden person';
  END IF;
  -- Hver facitrække findes.
  FOR r IN SELECT tabel, pk FROM purge_test.forventet LOOP
    IF to_regclass(r.tabel) IS NULL THEN RAISE EXCEPTION 'PURGE_FIXTURE_KONTROL: ukendt tabel %', r.tabel; END IF;
    EXECUTE format('SELECT count(*) FROM %s t WHERE to_jsonb(t) @> $1', r.tabel) INTO n USING r.pk;
    IF n <> 1 THEN RAISE EXCEPTION 'PURGE_FIXTURE_KONTROL: facitrække % % findes % gange', r.tabel, r.pk, n; END IF;
  END LOOP;
  -- P skal kunne slettes: ingen blokering (S20/NY-A, S29, samme_som-knudepunkt).
  IF EXISTS (SELECT 1 FROM public.assertion WHERE (objekt_type='person' AND objekt_id=v_p)
                OR (objekt_type='family' AND objekt_id=purge_test.id('fam_del'))) THEN
    RAISE EXCEPTION 'PURGE_FIXTURE_KONTROL: påstand med objekt P/fam_del (blokering)';
  END IF;
  IF EXISTS (SELECT 1 FROM public.text_mention WHERE maal_type='person' AND maal_id=v_p) THEN
    RAISE EXCEPTION 'PURGE_FIXTURE_KONTROL: levende link til P i andres prosa (blokering)';
  END IF;
  IF (SELECT count(*) FROM public.relation WHERE rolle='samme_som' AND subjekt_type='person' AND objekt_type='person'
        AND v_p IN (subjekt_id,objekt_id)) <> 1 THEN
    RAISE EXCEPTION 'PURGE_FIXTURE_KONTROL: P skal have præcis én samme_som-nabo';
  END IF;
  -- Sættenes form.
  IF (SELECT summary FROM public.change_set WHERE id=purge_test.id('saet_opret_P')) <> 'Oprettede person Testperson Purge'
     OR EXISTS (SELECT 1 FROM public.change_event e WHERE e.change_set_id=purge_test.id('saet_opret_P')
                 AND NOT (e.tabel='person' AND e.row_pk->>'id'=v_p::text)
                 AND NOT (e.tabel='fact' AND (e.efter->>'subjekt_id')=v_p::text)
                 AND NOT (e.tabel IN ('assertion','citation','conclusion'))) THEN
    RAISE EXCEPTION 'PURGE_FIXTURE_KONTROL: oprettelsessættet for P har fremmede events';
  END IF;
  IF (SELECT count(*) FROM public.change_event WHERE change_set_id=purge_test.id('saet_union_del')) <> 3
     OR (SELECT count(*) FROM public.change_event WHERE change_set_id=purge_test.id('saet_union_keep')) <> 3
     OR (SELECT count(*) FROM public.change_event WHERE change_set_id=purge_test.id('faelles_saet')) <> 8
     OR EXISTS (SELECT 1 FROM public.change_event WHERE change_set_id=purge_test.id('saet_withdraw'))
     OR (SELECT reverterer_id FROM public.change_set WHERE id=purge_test.id('saet_fortryd_bevaret'))
          <> purge_test.id('saet_union_keep') THEN
    RAISE EXCEPTION 'PURGE_FIXTURE_KONTROL: historiksættenes eventantal';
  END IF;
  -- §2.4: hvilke sæt slettes og hvilke bevares (facit på sætniveau).
  IF EXISTS (SELECT 1 FROM purge_test.forventet WHERE tabel='change_set' AND pk->>'id' IN (
               purge_test.id('saet_union_keep')::text, purge_test.id('faelles_saet')::text,
               purge_test.id('saet_fortryd_bevaret')::text, purge_test.id('saet_medie_delt')::text,
               purge_test.id('saet_note_tredje_link_i_foer')::text))
     OR (SELECT count(*) FROM purge_test.forventet WHERE tabel='change_set' AND pk->>'id' IN (
               purge_test.id('saet_opret_P')::text, purge_test.id('saet_fortryd_opret_P')::text,
               purge_test.id('saet_union_del')::text, purge_test.id('saet_withdraw')::text,
               purge_test.id('saet_tidligere_slettet')::text, purge_test.id('saet_note_flyttet')::text)) <> 6 THEN
    RAISE EXCEPTION 'PURGE_FIXTURE_KONTROL: facit på sætniveau';
  END IF;
  -- Hændelserne er indlæst uden historik.
  IF EXISTS (SELECT 1 FROM public.change_event WHERE tabel='haendelse') THEN
    RAISE EXCEPTION 'PURGE_FIXTURE_KONTROL: hændelser blev logget';
  END IF;
  -- Task 9: tredjes levende note = efter i det sidste event (ellers rammer fortryd divergens før dødt-link-tjekket).
  IF (SELECT to_jsonb(nt) FROM public.note nt WHERE nt.id=purge_test.id('note_tredje'))
     IS DISTINCT FROM (SELECT efter FROM public.change_event WHERE change_set_id=purge_test.id('saet_note_tredje_link_i_foer'))
     OR (SELECT foer->>'indhold' FROM public.change_event WHERE change_set_id=purge_test.id('saet_note_tredje_link_i_foer'))
        NOT LIKE '%[[person:'||v_p||'|Testperson Purge]]%' THEN
    RAISE EXCEPTION 'PURGE_FIXTURE_KONTROL: tredjes note';
  END IF;
END $$;

COMMIT;
