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
-- Task 2b (afsnittet »ledgers og identitet« før kontrollen) dækker S10-S12, S22-S24, S33b, S36 og §1e, herunder R3
-- (det fælles sæts narrative_publication_event) og R11 (paadennedag:<P>:født:<år>). S9 kan ikke forekomme: kvitteringen
-- forbruges i den oprettende transaktion. Filen kræver kontrakt v2 (reimport-writer-v2-bootstrap.sql før fixturen).
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
-- Task 2b: ledgers og identitet (slettegraf §1a S9-S12, §1c S22-S24, S33b, S36, §1e, §3).
--
-- Verdenen bygges i kilde A (DAA-udgave, P's eneste nøglede external-id PURGE-P), så P ikke får et tredje
-- external-id. Rækkefølgen er bindende:
--   1. publiceringsverden: records, narrativer med publiceret binding, B-batch (publication_persona) og C-batch
--      (publication_identity) gennem de rigtige writere → X1 (P's publiceringspersona) og T1 (tredjes);
--   2. identitetsstrømme med red_afgoer_source_persona (før enhver kontrolkørsel): X2 med tre events (accepted → tredje,
--      rejected, accepted → P) og Y (accepted → P, accepted → tredje);
--   3. fortolkninger på X2 (forslag, afgørelse, påstandsrettelse, binding, familiebinding, genåbning, afstemning);
--   4. ledgers uden skriver for netop denne P (fabrikeret med direkte INSERT, men gennem alle valideringstriggere):
--      navnefuldførelse, C3-tildeling, publiceringshændelser, legacy-publicering, kontrolkørsel med forældrekort;
--   5. legacy-disposition (private.record_legacy_disposition), beskrivelseskilde og feed-pin paadennedag:P:født:<år>.
-- Alle tekster er neutrale (ingen navne). Intet her blokerer sletningen af P (kontrolleres sidst i filen).
-- purge_test.sted(sted, tabel, pk): én repræsentant pr. 2b-sted, så delsteder bag en samlet tæller (S11a/S11b, S39a/
-- Prom_egen_fam, S45a/M5, S49a/S49b) kan efterprøves hver for sig.
\i tests/sql/fixtures/publication-identity.sql
\i tests/sql/fixtures/relation-5b.sql

CREATE TABLE purge_test.sted(sted text NOT NULL, tabel text NOT NULL, pk jsonb NOT NULL, PRIMARY KEY (sted,tabel,pk));
COMMENT ON TABLE purge_test.sted IS
  'Task 2b: repræsentantrækker pr. slettegraf-sted (delsteder bag en samlet tæller i person-purge-count.sql).';
CREATE TABLE purge_test.uid(rolle text PRIMARY KEY, id uuid NOT NULL);
CREATE FUNCTION purge_test.u(p_rolle text) RETURNS uuid LANGUAGE plpgsql STABLE AS $$
DECLARE v uuid;
BEGIN
  SELECT id INTO v FROM purge_test.uid WHERE rolle=p_rolle;
  IF v IS NULL THEN RAISE EXCEPTION 'PURGE_FIXTURE: ukendt uuid-rolle %', p_rolle; END IF;
  RETURN v;
END $$;
CREATE FUNCTION purge_test.gem_u(p_rolle text, p_id uuid) RETURNS uuid LANGUAGE sql AS $$
  INSERT INTO purge_test.uid(rolle,id) VALUES (p_rolle,p_id) RETURNING id;
$$;
-- Facitrække + repræsentant for stedet.
CREATE FUNCTION purge_test.fs(p_sted text, p_tabel text, p_pk jsonb, p_handling text DEFAULT 'slet') RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM purge_test.f(p_tabel,p_pk,p_handling);
  INSERT INTO purge_test.sted(sted,tabel,pk) VALUES (p_sted,p_tabel,p_pk) ON CONFLICT DO NOTHING;
END $$;

-- Kilde A's publiceringsramme (som pp_source, men på den eksisterende kilde og med purge-redaktøren som aktør) og en
-- helpost for en eksisterende person (som pp_post uden person-INSERT; external-id'et skrives kun, hvis det mangler).
CREATE FUNCTION pg_temp.pt_source(p_source bigint, p_actor uuid) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_run uuid:=gen_random_uuid(); v_rend uuid; v_cfg jsonb; v_sha text;
BEGIN
  INSERT INTO private.extraction_run(id,source_id,run_key,schema_version,extractor_version,profile_version,input_sha256,manifest)
    VALUES (v_run,p_source,'purge-fixture-'||v_run::text,'fixture','fixture','fixture',repeat('1',64),'{}');
  INSERT INTO private.source_rendition(source_id,rendition_key,rendition_kind,content_sha256,metadata)
    VALUES (p_source,'purge-r1','pdf_text_layer',repeat('2',64),'{}') RETURNING id INTO v_rend;
  v_cfg:=jsonb_build_object('citation_label_template','Synthetic side {page_from}','extractor_version','publication-v1',
    'observation_extraction_method','clause_segment_v1','rendition_key','fixture-r1','rendition_kind','pdf_text_layer',
    'rendition_metadata',jsonb_build_object('edition','fixture'),'run_key_prefix','reimport-publication:',
    'schema_version','clause-evidence-manifest-v1','text_form','raw','helpost_observation_kind','person','persona_key_prefix','1939:');
  v_sha:=private.reimport_canonical_json_sha256(v_cfg);
  INSERT INTO private.reimport_writer_profile(source_id,profile_id,profile_version,profile_sha256,writer_config)
    VALUES (p_source,'fixture-pub-a','publication-v1',v_sha,v_cfg);
  RETURN jsonb_build_object('source',p_source,'run',v_run,'rend',v_rend,'actor',p_actor,'profile_sha256',v_sha);
END $$;

CREATE FUNCTION pg_temp.pt_post(p_src jsonb, p_key text, p_person bigint, p_nr int) RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE v_source bigint:=(p_src->>'source')::bigint; v_rec uuid; v_obs uuid; v_mention uuid; v_text text:='Fixture Navn '||p_key;
  v_narr bigint; v_binding uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.person_external_id WHERE person_id=p_person AND source_id=v_source) THEN
    INSERT INTO public.person_external_id(person_id,source_id,linje,nr,record_key) VALUES (p_person,v_source,'T',p_nr,p_key);
  END IF;
  INSERT INTO private.source_record(source_id,record_key,record_kind,created_run_id) VALUES (v_source,p_key,'person',(p_src->>'run')::uuid)
    RETURNING id INTO v_rec;
  v_obs:=pg_temp.pp_occ(v_rec,p_src,p_key||'-h',100,500,'person',v_text);
  INSERT INTO private.source_mention(observation_id,mention_kind,char_from,char_to,verbatim_text,created_run_id)
    VALUES (v_obs,'person',0,char_length(v_text),v_text,(p_src->>'run')::uuid) RETURNING id INTO v_mention;
  INSERT INTO public.narrative(subjekt_type,subjekt_id,source_id,side,tekst) VALUES ('person',p_person,v_source,'1','Syntetisk tekst '||p_key)
    RETURNING id INTO v_narr;
  INSERT INTO private.narrative_record_publication(narrative_id,source_record_id,record_label,citation_label,status)
    VALUES (v_narr,v_rec,'Fixture '||p_key,'Fixture side 1','published') RETURNING id INTO v_binding;
  RETURN jsonb_build_object('record_key',p_key,'record',v_rec,'person',p_person,'binding',v_binding,'narrative',v_narr,
    'mention',v_mention,'mention_sha',encode(extensions.digest(v_text,'sha256'),'hex'),'observation',v_obs);
END $$;

-- Én redaktørafgørelse af en persona (web_detail), som detaljesiden; returnerer den nye version.
CREATE FUNCTION pg_temp.pt_afgoer(p_persona uuid, p_version int, p_action text, p_person bigint) RETURNS int LANGUAGE plpgsql AS $$
DECLARE v int;
BEGIN
  PERFORM purge_test.nyt();
  SET LOCAL ROLE authenticated;
  v:=public.red_afgoer_source_persona(p_persona,p_version,p_action,p_person,'Afgjort fra detaljesiden.');
  RESET ROLE;
  RETURN v;
END $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- 1. Publiceringsverden i kilde A: P's helpost PURGE-P (P's eksisterende external-id) og tredjes PURGE-T.
DO $$
DECLARE v_actor uuid:='a2a00000-0000-4000-8000-00000000a001'; v_src jsonb; v_fp jsonb; v_ft jsonb; v_els jsonb;
  v_b uuid; v_c uuid; v_x1 uuid; v_t1 uuid; v_run uuid; w jsonb; v_cands jsonb; v_pl jsonb:='[]'::jsonb; v_i int;
  v_out text; v_ans text; v_sample uuid[]; v_p bigint:=purge_test.id('P'); v_e bigint;
BEGIN
  v_src:=pg_temp.pt_source(purge_test.id('kilde_a'),v_actor);
  v_fp:=pg_temp.pt_post(v_src,'PURGE-P',v_p,1);
  v_ft:=pg_temp.pt_post(v_src,'PURGE-T',purge_test.id('tredje'),2);
  PERFORM purge_test.gem('narrativ_P_kilde_a',(v_fp->>'narrative')::bigint);
  PERFORM purge_test.gem_u('record_P',(v_fp->>'record')::uuid);
  PERFORM purge_test.gem_u('binding_P',(v_fp->>'binding')::uuid);
  PERFORM purge_test.f('narrative',jsonb_build_object('id',(v_fp->>'narrative')::bigint));
  PERFORM purge_test.fs('S22','private.narrative_record_publication',jsonb_build_object('id',v_fp->>'binding'));

  -- B-batch: begge helposter → personas X1 (P) og T1 (tredje).
  v_els:=jsonb_build_object('publication-persona:PURGE-P',pg_temp.pp_payload(v_src,v_fp),
                            'publication-persona:PURGE-T',pg_temp.pp_payload(v_src,v_ft));
  v_b:=pg_temp.pp_begin(v_src,'fixture-pub-a','B-purge',v_els);
  PERFORM pg_temp.pp_apply(v_src,v_b,'publication-persona:PURGE-P',v_els->'publication-persona:PURGE-P');
  PERFORM pg_temp.pp_apply(v_src,v_b,'publication-persona:PURGE-T',v_els->'publication-persona:PURGE-T');
  PERFORM set_config('role','authenticated',true);
  PERFORM public.red_finalize_reimport(v_b);
  RESET role;
  SELECT (payload->'result_receipt'->>'source_persona_id')::uuid, id INTO v_x1, v_e FROM private.reimport_event
   WHERE batch_id=v_b AND element_id='publication-persona:PURGE-P';
  PERFORM purge_test.fs('S41a','private.reimport_event',jsonb_build_object('id',v_e));
  SELECT (payload->'result_receipt'->>'source_persona_id')::uuid INTO v_t1 FROM private.reimport_event
   WHERE batch_id=v_b AND element_id='publication-persona:PURGE-T';
  PERFORM purge_test.gem_u('b_batch',v_b); PERFORM purge_test.gem_u('X1',v_x1); PERFORM purge_test.gem_u('T1',v_t1);

  -- Kandidatkørsel (list-tilstand over X1 og T1): X1 → P (S12), T1 → tredje.
  w:=jsonb_build_object('src',v_src,'b_batch',v_b,'posts',jsonb_build_array(v_fp,v_ft),
                        'personas',jsonb_build_array(v_x1::text,v_t1::text));
  v_cands:=jsonb_build_array(
    pg_temp.pi_cand(v_x1,v_p,1,jsonb_build_array(pg_temp.pi_ms(v_p,0.95,ARRAY['name','birth']))),
    pg_temp.pi_cand(v_t1,purge_test.id('tredje'),1,jsonb_build_array(pg_temp.pi_ms(purge_test.id('tredje'),0.95,ARRAY['name','birth']))));
  v_run:=pg_temp.pi_run(w,'{"topK":10,"autoCutoff":0.9,"controlMargin":0.05}',v_cands);
  PERFORM purge_test.gem_u('kandidatkoersel',v_run);
  PERFORM purge_test.gem_u('kandidat_P',(SELECT id FROM private.source_persona_identity_candidate
                                          WHERE run_id=v_run AND candidate_person_id=v_p));
  PERFORM purge_test.fs('S12','private.source_persona_identity_candidate',jsonb_build_object('id',purge_test.u('kandidat_P')));

  -- C-batch: udfaldet er klassifikatorens; i stikprøven svarer arket S.
  v_sample:=ARRAY(SELECT private.publication_control_sample(v_run));
  FOR v_i IN 1..2 LOOP
    v_out:=private.publication_control_outcome((w->'personas'->>(v_i-1))::uuid,v_run,(w->'posts'->(v_i-1)->>'person')::bigint)->>'outcome';
    v_ans:=CASE WHEN (w->'personas'->>(v_i-1))::uuid=ANY(v_sample) OR v_out IN ('uenig','navnefaelle') THEN 'S' END;
    v_pl:=v_pl||jsonb_build_array(pg_temp.pi_payload(w,v_i,v_run,v_out,v_ans));
  END LOOP;
  v_c:=pg_temp.pi_begin(w,'C-purge',pg_temp.pi_elements(v_pl));
  FOR v_i IN 0..1 LOOP
    PERFORM pg_temp.pi_apply(w,v_c,pg_temp.pi_el(v_pl->v_i),v_pl->v_i);
  END LOOP;
  PERFORM pg_temp.pi_finalize(w,v_c);
  PERFORM purge_test.gem_u('c_batch',v_c);
  SELECT id INTO v_e FROM private.reimport_event WHERE batch_id=v_c AND element_id='publication-identity:'||v_x1;
  PERFORM purge_test.fs('S41a','private.reimport_event',jsonb_build_object('id',v_e));
  -- X1's identitet: v1 accepted → P (S10, S11a).
  PERFORM purge_test.fs('S10','private.source_persona_identity',
    jsonb_build_object('source_persona_id',v_x1,'canonical_person_id',v_p));
  PERFORM purge_test.fs('S11a','private.source_persona_identity_event',
    jsonb_build_object('id',(SELECT id FROM private.source_persona_identity_event WHERE source_persona_id=v_x1 AND version=1)));
END $$;
SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;

-- ---------------------------------------------------------------------------------------------------------------------
-- 2. Identitetsstrømme (før kontrolkørslen; red_afgoer_source_persona nægter personas i en uforseglet stikprøve).
--    X2: v1 accepted → tredje (K-3), v2 rejected, v3 accepted → P → hel_stroem (alle tre slettes).
--    Y : v1 accepted → P (S11b, slettes), v2 accepted → tredje (bevares; strømmen får et hul).
DO $$
DECLARE v_actor uuid:='a2a00000-0000-4000-8000-00000000a001';
  v_src jsonb:=jsonb_build_object('run',(SELECT id FROM private.extraction_run WHERE source_id=purge_test.id('kilde_a')
                                           AND run_key LIKE 'purge-fixture-%'),
                                  'rend',(SELECT id FROM private.source_rendition WHERE source_id=purge_test.id('kilde_a')
                                           AND rendition_key='purge-r1'));
  v_px jsonb; v_py jsonb; v_x2 uuid; v_y uuid; v_p bigint:=purge_test.id('P'); v_t bigint:=purge_test.id('tredje'); r record;
BEGIN
  v_px:=pg_temp.f5b_post(purge_test.id('kilde_a'),v_src,'PURGE-X2','Post X2. Gift med Bo Beta.',
                         ARRAY['Post X2.','Gift med Bo Beta.'],NULL,v_actor);
  v_py:=pg_temp.f5b_post(purge_test.id('kilde_a'),v_src,'PURGE-Y','Post Y. Nævnt.',ARRAY['Post Y.','Nævnt.'],NULL,v_actor);
  v_x2:=(v_px->>'principal')::uuid; v_y:=(v_py->>'principal')::uuid;
  PERFORM purge_test.gem_u('X2',v_x2); PERFORM purge_test.gem_u('Y',v_y);
  PERFORM purge_test.gem_u('X2_klausul',(v_px->'clauses'->>1)::uuid);
  PERFORM purge_test.gem_u('X2_record',(v_px->>'record')::uuid);
  IF pg_temp.pt_afgoer(v_x2,0,'same',v_t)<>1 OR pg_temp.pt_afgoer(v_x2,1,'different',NULL)<>2
     OR pg_temp.pt_afgoer(v_x2,2,'same',v_p)<>3
     OR pg_temp.pt_afgoer(v_y,0,'same',v_p)<>1 OR pg_temp.pt_afgoer(v_y,1,'same',v_t)<>2 THEN
    RAISE EXCEPTION 'PURGE_FIXTURE: identitetsversioner';
  END IF;
  PERFORM purge_test.nyt();
  PERFORM purge_test.fs('S10','private.source_persona_identity',
    jsonb_build_object('source_persona_id',v_x2,'canonical_person_id',v_p));
  FOR r IN SELECT id, version FROM private.source_persona_identity_event WHERE source_persona_id=v_x2 ORDER BY version LOOP
    PERFORM purge_test.fs('S11a','private.source_persona_identity_event',jsonb_build_object('id',r.id));
  END LOOP;
  PERFORM purge_test.fs('S11b','private.source_persona_identity_event',
    jsonb_build_object('id',(SELECT id FROM private.source_persona_identity_event WHERE source_persona_id=v_y AND version=1)));
END $$;
SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;

-- ---------------------------------------------------------------------------------------------------------------------
-- 3. Fortolkninger på X2 (P's egen persona, kilde A).
--    a) Et importeret tilnavn på P, citeret af kilde A (som indlæseren, under et sæt med subjekt P) → slettes helt.
--    b) Forslag person.byname fra X2, afgjort accepted (red_decide_interpretation).
--    c) red_ret_paastand retter påstanden til forslagets værdi → paastand_korrektion (S36) og sættets UPDATE-event.
--    d) Bindingen af forslaget til påstanden (red_preview_/red_promote_interpretations_batch) → Prom_egen (S39a).
--    e) relation.marriage fra X2 (principal-persona, som forslagswriteren skriver persona_role='principal'), afgjort og
--       bundet til den bevarede familie fam_keep (red_promote_interpretation, familiemål med state_sha256) → Prom_egen_fam.
--    f) Genåbning af familiebindingen til fam_del (relation_reopen, S49a); ny version v3 af fortolkningen.
--    g) Afstemning efter tekstrevision (text_revision_reconciliation, S49b): Prom_egen tilbagetrukket; revisionshændelsen
--       er P's publication_persona-hændelse (S41a), så begge FK-veje i fase 2a er dækket.
DO $$
DECLARE v_actor uuid:='a2a00000-0000-4000-8000-00000000a001'; v_p bigint:=purge_test.id('P');
  v_ka bigint:=purge_test.id('kilde_a'); v_x2 uuid:=purge_test.u('X2'); v_obs uuid:=purge_test.u('X2_klausul');
  v_run uuid; v_f bigint; v_a bigint; v_i1 uuid:=gen_random_uuid(); v_i2 uuid; v_m1 uuid:=gen_random_uuid(); v_m2 uuid;
  v_m3 uuid:=gen_random_uuid(); v_key_m uuid:=gen_random_uuid(); v_key_t uuid:=gen_random_uuid(); j jsonb; items jsonb; pv jsonb;
  v_prom uuid; v_prom_fam uuid; v_cs bigint;
BEGIN
  SELECT created_run_id INTO v_run FROM private.source_persona WHERE id=v_x2;
  -- a)
  PERFORM purge_test.nyt();
  PERFORM public.begin_change_set('purge_test_import_tilnavn',format('Importerede tilnavn på person %s',v_p),'person',v_p);
  INSERT INTO public.fact(subjekt_type,subjekt_id,faktatype) VALUES ('person',v_p,'tilnavn') RETURNING id INTO v_f;
  INSERT INTO public.assertion(target_type,target_id,vaerdi_tekst,uforanderlig) VALUES ('fact',v_f,'Purgemand',true)
    RETURNING id INTO v_a;
  INSERT INTO public.conclusion(target_type,target_id,valgt_assertion_id,status) VALUES ('fact',v_f,v_a,'afklaret');
  INSERT INTO public.citation(assertion_id,source_id,citat_tekst,side) VALUES (v_a,v_ka,'Purgekilde A','3');
  PERFORM purge_test.gem('fakta_tilnavn',v_f); PERFORM purge_test.gem('assertion_tilnavn',v_a);
  PERFORM purge_test.f_saet_helt(purge_test.saet());
  -- b)
  PERFORM purge_test.nyt();
  INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,
    predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
    VALUES (v_i1,v_key_t,1,v_ka,v_x2,'property','person.byname',to_jsonb('Purgemanden'::text),'1.0','source_statement',1,
            'proposed','fixture',v_run);
  INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
    VALUES (v_i1,v_obs,'supporting',1);
  SET LOCAL ROLE authenticated;
  v_i2:=public.red_decide_interpretation(v_i1,1,'accepted','{"basis":"purge-fixture"}');
  RESET ROLE;
  -- c)
  PERFORM purge_test.nyt();
  SET LOCAL ROLE authenticated;
  j:=public.red_ret_paastand(v_a,jsonb_build_object('fact_id',v_f,'faktatype','tilnavn','vaerdi_tekst','Purgemand',
       'date_raw',NULL,'valgt_assertion_id',v_a,'citation_sources',jsonb_build_array(v_ka)),'bogen_har_ret',v_i2);
  RESET ROLE;
  v_cs:=(j->>'change_set_id')::bigint;
  PERFORM purge_test.gem('saet_paastand',v_cs);
  PERFORM purge_test.f_saet_helt(v_cs,false);
  PERFORM purge_test.fs('S36','paastand_korrektion',jsonb_build_object('id',(j->>'korrektion_id')::bigint));
  -- d)
  PERFORM purge_test.nyt();
  SET LOCAL ROLE authenticated;
  items:=jsonb_build_array(jsonb_build_object('interpretation_id',v_i2::text,'target_type','assertion','target_id',v_a));
  pv:=public.red_preview_interpretation_promotions(items);
  PERFORM public.red_promote_interpretations_batch(items,pv->>'preview_hash');
  RESET ROLE;
  PERFORM purge_test.nyt();
  SELECT id INTO v_prom FROM private.interpretation_promotion
   WHERE interpretation_id=v_i2 AND target_type='assertion' AND target_id=v_a;
  IF v_prom IS NULL THEN RAISE EXCEPTION 'PURGE_FIXTURE: ingen promotion af tilnavnet'; END IF;
  PERFORM purge_test.gem_u('prom_egen',v_prom);
  PERFORM purge_test.fs('S39a','private.interpretation_promotion',jsonb_build_object('id',v_prom));
  -- e)
  INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,
    predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id)
    VALUES (v_m1,v_key_m,1,v_ka,v_x2,'relation','relation.marriage',
            jsonb_build_object('raw','Gift med Bo Beta.','normalized','Gift med Bo Beta.'),'fixture','model_inference',0.9,
            'proposed','fixture',v_run);
  INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
    VALUES (v_m1,v_obs,'supporting',1);
  SET LOCAL ROLE authenticated;
  v_m2:=public.red_decide_interpretation(v_m1,1,'accepted','{"basis":"purge-fixture"}');
  RESET ROLE;
  v_prom_fam:=public.red_promote_interpretation(v_m2,'family',purge_test.id('fam_keep'),
    jsonb_build_object('state_sha256',encode(extensions.digest('purge-fixture-fam-keep','sha256'),'hex'),
                       'basis','purge-fixture'));
  PERFORM purge_test.gem_u('prom_egen_fam',v_prom_fam);
  PERFORM purge_test.fs('Prom_egen_fam','private.interpretation_promotion',jsonb_build_object('id',v_prom_fam));
  -- f)
  INSERT INTO private.interpretation(id,interpretation_key,version,source_id,source_persona_id,interpretation_kind,
    predicate,value,schema_version,derivation_kind,confidence,status,method,extraction_run_id,supersedes_id)
    SELECT v_m3,interpretation_key,3,source_id,source_persona_id,interpretation_kind,predicate,value,schema_version,
           derivation_kind,confidence,'proposed',method,extraction_run_id,id
      FROM private.interpretation WHERE id=v_m2;
  INSERT INTO private.interpretation_observation(interpretation_id,observation_id,evidence_role,ordinal)
    VALUES (v_m3,v_obs,'supporting',1);
  INSERT INTO private.relation_reopen(to_interpretation_id,interpretation_key,from_interpretation_id,superseded_promotion_id,
    from_family_id,to_family_id,spouse_source_persona_id,spouse_identity_version,note,context,reopened_by,reopened_by_name)
    VALUES (v_m3,v_key_m,v_m2,v_prom_fam,purge_test.id('fam_keep'),purge_test.id('fam_del'),purge_test.u('Y'),2,
            'Genåbnet efter identitetsrettelse.','{"fixture":"purge"}',v_actor,'Purge-redaktør');
  PERFORM purge_test.fs('S49a','private.relation_reopen',jsonb_build_object('to_interpretation_id',v_m3));
  -- g)
  INSERT INTO private.text_revision_reconciliation(revision_batch_id,revision_element_id,old_interpretation_key,
    old_promotion_id,outcome,context,decided_by,decided_by_name)
    VALUES (purge_test.u('b_batch'),'publication-persona:PURGE-P',v_key_t,v_prom,'tilbagetrukket','{"fixture":"purge"}',
            v_actor,'Purge-redaktør');
  PERFORM purge_test.fs('S49b','private.text_revision_reconciliation',
    jsonb_build_object('id',(SELECT id FROM private.text_revision_reconciliation WHERE old_promotion_id=v_prom)));
END $$;
SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;

-- ---------------------------------------------------------------------------------------------------------------------
-- 4. Ledgers, hvor ingen skriver kan lave rækken for netop denne P (fabrikeret, direkte INSERT, forælder før barn).
--    Alle rækker passerer tabellernes valideringstriggere; ingen batch/autorisation står åben/udstedt, og
--    kontrolkørslen er terminal (failed), så intet blokerer P.
--    a) R3: publiceringshændelse på P's binding (S23), ført under det fælles sæt (subjekt anden_partner). Sættet bevares
--       (andres events), men FK'en npe.change_set_id skal være væk før sæt-fasen.
--    b) Legacy-publicering af P's narrativ (S24): grandfathered → withdrawn med en legacy_withdrawn-hændelse under
--       2a's withdraw-sæt (saet_withdraw, 0 change_events, som withdraw_legacy_narrative); latest_event_id peger på
--       hændelsen (fase 3a nulstiller den, før 3b sletter hændelsen).
--    c) Navnefuldførelse (S42): writeren kræver en staged, navnløs person fra en person_create-hændelse; P er oprettet af
--       red_opret_person. Rækken peger på B-/C-batchen og P's navnefaktum (fabrikeret).
--    d) C3-tildeling (S43a): reimport_case_event record_assign med target_person_id=P i en finaliseret case-batch.
--    e) Kontrolkørsel på kandidatkørslen (terminal: sealed → failed) med stikprøve på X1, hvis mapping/expected er P's
--       kandidat-uuid (S46, bevar_andres), og et forældrekort med counterpart_person_id=P (S45a) og dets event (M5).
DO $$
DECLARE v_actor uuid:='a2a00000-0000-4000-8000-00000000a001'; v_p bigint:=purge_test.id('P');
  v_ka bigint:=purge_test.id('kilde_a'); v_kb bigint:=purge_test.id('kilde_b'); v_e uuid; v_ref uuid:='a2a00000-0000-4000-8000-0000000000c1';
  v_st jsonb; v_sha text; v_auth uuid; v_batch uuid; v_ev bigint; v_run uuid; v_smp uuid; v_card uuid; v_nf bigint; r record;
  v_sheet text:=repeat('a',64); v_rows text:=repeat('b',64);
BEGIN
  -- a)
  v_st:=jsonb_build_object('fixture','purge','status','published');
  v_sha:=encode(extensions.digest(v_st::text,'sha256'),'hex');
  INSERT INTO private.narrative_publication_event(change_set_id,stream_ref,stream_version,event_type,binding_id,narrative_id,
    source_id,source_record_id,decision_basis,before_state,after_state,before_state_sha256,after_state_sha256,decided_by,
    decided_by_name)
    VALUES (purge_test.id('faelles_saet'),purge_test.u('binding_P'),1,'published',purge_test.u('binding_P'),
            purge_test.id('narrativ_P_kilde_a'),v_ka,purge_test.u('record_P'),'purge-fixture','{}',v_st,
            encode(extensions.digest('{}','sha256'),'hex'),v_sha,v_actor,'Purge-redaktør')
    RETURNING id INTO v_e;
  PERFORM purge_test.gem_u('npe_faelles',v_e);
  PERFORM purge_test.fs('S23','private.narrative_publication_event',jsonb_build_object('id',v_e));
  -- b)
  v_st:=jsonb_build_object('fixture','purge','status','grandfathered_publication');
  INSERT INTO private.narrative_legacy_publication(legacy_publication_ref,narrative_id,source_id,baseline_state,baseline_sha256,status)
    VALUES (v_ref,purge_test.id('narrativ_P'),v_kb,v_st,encode(extensions.digest(v_st::text,'sha256'),'hex'),
            'grandfathered_publication');
  UPDATE private.narrative_legacy_publication SET status='withdrawn' WHERE legacy_publication_ref=v_ref;
  INSERT INTO private.narrative_publication_event(change_set_id,stream_ref,stream_version,event_type,narrative_id,
    source_id,legacy_publication_ref,decision_basis,before_state,after_state,before_state_sha256,after_state_sha256,decided_by,
    decided_by_name)
    VALUES (purge_test.id('saet_withdraw'),v_ref,1,'legacy_withdrawn',purge_test.id('narrativ_P'),v_kb,v_ref,
            'trukket tilbage',v_st,jsonb_build_object('fixture','purge','status','withdrawn'),
            encode(extensions.digest(v_st::text,'sha256'),'hex'),repeat('d',64),v_actor,'Purge-redaktør')
    RETURNING id INTO v_e;
  UPDATE private.narrative_legacy_publication SET latest_event_id=v_e WHERE legacy_publication_ref=v_ref;
  PERFORM purge_test.gem_u('npe_legacy',v_e);
  PERFORM purge_test.fs('S23','private.narrative_publication_event',jsonb_build_object('id',v_e));
  PERFORM purge_test.fs('S24','private.narrative_legacy_publication',jsonb_build_object('legacy_publication_ref',v_ref));
  -- c)
  SELECT f.id AS fact_id, c.valgt_assertion_id AS assertion_id, ci.id AS citation_id, c.id AS conclusion_id INTO r
    FROM public.fact f JOIN public.conclusion c ON c.target_type='fact' AND c.target_id=f.id
    JOIN public.citation ci ON ci.assertion_id=c.valgt_assertion_id
   WHERE f.subjekt_type='person' AND f.subjekt_id=v_p AND f.faktatype='navn' ORDER BY ci.id LIMIT 1;
  INSERT INTO private.reimport_name_completion_result(batch_id,element_id,source_batch_id,person_id,source_record_id,
    source_persona_id,fact_id,assertion_id,citation_id,conclusion_id,payload_sha256,result_sha256)
    VALUES (purge_test.u('c_batch'),'name-completion:PURGE-P',purge_test.u('b_batch'),v_p,purge_test.u('record_P'),
            purge_test.u('X1'),r.fact_id,r.assertion_id,r.citation_id,r.conclusion_id,repeat('e',64),repeat('f',64));
  PERFORM purge_test.fs('S42','private.reimport_name_completion_result',
    jsonb_build_object('id',(SELECT id FROM private.reimport_name_completion_result WHERE person_id=v_p)));
  -- d)
  INSERT INTO private.reimport_case_authorization(source_id,phase,operation,manifest_sha256,preview_sha256,approval_sha256,
    decisions_sha256,state_sha256,text_bundle_sha256,database_name,system_identifier,expected_counts,authorized_elements,
    principal_id,nonce,expires_at,status,consumed_at)
    VALUES (v_ka,'c3','apply',repeat('1',64),repeat('2',64),repeat('3',64),repeat('4',64),repeat('5',64),repeat('6',64),
            current_database(),(pg_control_system()).system_identifier::text,'{"record_assign":1}',
            jsonb_build_object('case:PURGE:rid:PURGE-P',jsonb_build_object('action','record_assign')),v_actor,gen_random_uuid(),
            clock_timestamp()-interval '1 minute','consumed',clock_timestamp())
    RETURNING id INTO v_auth;
  INSERT INTO private.reimport_case_batch(authorization_id,source_id,phase,operation,manifest_sha256,preview_sha256,principal_id,
    status,expected_counts,observed_counts,finalized_at)
    VALUES (v_auth,v_ka,'c3','apply',repeat('1',64),repeat('2',64),v_actor,'finalized','{"record_assign":1}','{"record_assign":1}',
            clock_timestamp())
    RETURNING id INTO v_batch;
  INSERT INTO private.reimport_case_event(batch_id,source_id,phase,element_id,action,payload_schema_version,payload,after_sha256)
    VALUES (v_batch,v_ka,'c3','case:PURGE:rid:PURGE-P','record_assign','c3-apply-v1',
            jsonb_build_object('source_record_key','PURGE-P','target_person_id',v_p),repeat('7',64))
    RETURNING id INTO v_ev;
  PERFORM purge_test.fs('S43a','private.reimport_case_event',jsonb_build_object('id',v_ev));
  -- e)
  v_run:=purge_test.u('kandidatkoersel');
  INSERT INTO private.identity_control_run(source_id,candidate_run_id,identity_population_sha256,relation_population_sha256,
    input_list_sha256,created_by)
    VALUES (v_ka,v_run,repeat('8',64),repeat('9',64),repeat('0',64),v_actor) RETURNING id INTO v_run;
  PERFORM purge_test.gem_u('kontrolkoersel',v_run);
  INSERT INTO private.identity_control_sample(control_run_id,sample_kind,stratum,source_persona_id,identity_version,mapping,expected)
    VALUES (v_run,'identity','single_family',purge_test.u('X1'),1,
            jsonb_build_object('1',purge_test.u('kandidat_P')::text),purge_test.u('kandidat_P')::text)
    RETURNING id INTO v_smp;
  PERFORM purge_test.gem_u('stikproeve_X1',v_smp);
  INSERT INTO private.identity_control_parent_card(control_run_id,interpretation_key,interpretation_version,family_id,
    counterpart_person_id,counterpart_persona_id,partner_ids)
    VALUES (v_run,gen_random_uuid(),1,purge_test.id('fam_keep'),v_p,purge_test.u('X2'),
            ARRAY[v_p,purge_test.id('anden_partner')])
    RETURNING id INTO v_card;
  PERFORM purge_test.fs('S45a','private.identity_control_parent_card',jsonb_build_object('id',v_card));
  PERFORM private.append_control_event(v_run,'sealed',NULL,v_sheet,v_rows);
  PERFORM private.append_parent_card_event(v_card,'F','Familien i basen passer ikke.',
    jsonb_build_object('sheet_sha256',v_sheet,'rows_sha256',v_rows,'line',1));
  PERFORM private.append_control_event(v_run,'failed','afvigelse');
  PERFORM purge_test.fs('M5','private.identity_control_parent_event',jsonb_build_object('card_id',v_card,'seq',1));
END $$;
SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;

-- ---------------------------------------------------------------------------------------------------------------------
-- 5. Legacy-disposition (private.record_legacy_disposition, S40), beskrivelsens kildekobling (S33b; ingen skriver) og
--    feed-pin i formatet paadennedag:<P>:født:<år> (R11; packages/feed/src/temporal.ts:78) via red_set_feed_pin.
DO $$
DECLARE v_p bigint:=purge_test.id('P'); v int;
BEGIN
  v:=private.record_legacy_disposition(v_p,purge_test.id('kilde_a'),'retained_legacy',NULL,
       '{"decided_by_name":"Purge-redaktør","reason":"purge-fixture"}');
  PERFORM purge_test.fs('S40','private.legacy_placement_disposition',
    jsonb_build_object('person_id',v_p,'source_id',purge_test.id('kilde_a'),'version',v));
  INSERT INTO private.entity_description_source(description_id,source_record_id,citation_note)
    VALUES (purge_test.id('beskrivelse_P'),purge_test.u('record_P'),'Purgekilde A, side 1');
  PERFORM purge_test.fs('S33b','private.entity_description_source',
    jsonb_build_object('description_id',purge_test.id('beskrivelse_P'),'source_record_id',purge_test.u('record_P')));
  PERFORM purge_test.nyt();
  PERFORM public.red_set_feed_pin('paadennedag:'||v_p||':født:1850','pin');
  PERFORM purge_test.f_saet_helt(purge_test.saet());
  INSERT INTO purge_test.sted(sted,tabel,pk)
    SELECT 'S32','feed_pin',jsonb_build_object('id',id) FROM public.feed_pin WHERE kort_noegle='paadennedag:'||v_p||':født:1850';
  PERFORM purge_test.nyt();
END $$;
SET CONSTRAINTS ALL IMMEDIATE; SET CONSTRAINTS ALL DEFERRED;

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

-- Kontrol af Task 2b: identitetsstrømmenes form, at hver repræsentant står i facit, og at intet blokerer P (slettegraf §4).
DO $$
DECLARE v_p bigint := purge_test.id('P'); v_t bigint := purge_test.id('tredje'); v_x2 uuid := purge_test.u('X2');
  v_y uuid := purge_test.u('Y'); v_x uuid[]; v_s text;
BEGIN
  v_x := ARRAY(SELECT source_persona_id FROM private.source_persona_identity
                WHERE decision_status='accepted' AND canonical_person_id=v_p ORDER BY 1);
  IF v_x IS DISTINCT FROM ARRAY(SELECT unnest(ARRAY[purge_test.u('X1'),v_x2]) ORDER BY 1) THEN
    RAISE EXCEPTION 'PURGE_FIXTURE_KONTROL: X skal være {X1, X2}';
  END IF;
  -- K-3/V2-1: X2's ældste event er accepted → tredje, før personaen blev koblet til P.
  IF (SELECT string_agg(version||':'||decision_status||':'||coalesce(canonical_person_id::text,'-'),',' ORDER BY version)
        FROM private.source_persona_identity_event WHERE source_persona_id=v_x2)
     IS DISTINCT FROM format('1:accepted:%s,2:rejected:-,3:accepted:%s',v_t,v_p) THEN
    RAISE EXCEPTION 'PURGE_FIXTURE_KONTROL: X2''s strøm';
  END IF;
  -- §6.10: Y har v1 accepted → P og v2 accepted → tredje (gældende).
  IF (SELECT string_agg(version||':'||decision_status||':'||coalesce(canonical_person_id::text,'-'),',' ORDER BY version)
        FROM private.source_persona_identity_event WHERE source_persona_id=v_y)
     IS DISTINCT FROM format('1:accepted:%s,2:accepted:%s',v_p,v_t)
     OR (SELECT canonical_person_id FROM private.source_persona_identity WHERE source_persona_id=v_y) IS DISTINCT FROM v_t THEN
    RAISE EXCEPTION 'PURGE_FIXTURE_KONTROL: Y''s strøm';
  END IF;
  -- Q6: Prom_egen_fam er en familiebinding på fam_keep fra P's egen persona.
  IF NOT EXISTS (SELECT 1 FROM private.interpretation_promotion p JOIN private.interpretation i ON i.id=p.interpretation_id
                  WHERE p.id=purge_test.u('prom_egen_fam') AND p.target_type='family'
                    AND p.target_id=purge_test.id('fam_keep') AND i.source_persona_id=ANY(v_x)) THEN
    RAISE EXCEPTION 'PURGE_FIXTURE_KONTROL: Prom_egen_fam';
  END IF;
  -- Hver repræsentant står i facit, og hvert 2b-delsted har mindst én.
  IF EXISTS (SELECT 1 FROM purge_test.sted s LEFT JOIN purge_test.forventet f USING (tabel,pk) WHERE f.tabel IS NULL) THEN
    RAISE EXCEPTION 'PURGE_FIXTURE_KONTROL: repræsentant uden facitrække';
  END IF;
  FOREACH v_s IN ARRAY ARRAY['S10','S11a','S11b','S12','S22','S23','S24','S32','S33b','S36','S39a','Prom_egen_fam','S40',
                             'S41a','S42','S43a','S45a','M5','S49a','S49b'] LOOP
    IF NOT EXISTS (SELECT 1 FROM purge_test.sted WHERE sted=v_s) THEN
      RAISE EXCEPTION 'PURGE_FIXTURE_KONTROL: intet repræsentant for %', v_s;
    END IF;
  END LOOP;
  -- §2.4: paastand-sættet slettes helt; det fælles sæt bevares trods npe-FK'en (R3), withdraw-sættet slettes.
  IF NOT EXISTS (SELECT 1 FROM purge_test.forventet WHERE tabel='change_set' AND pk->>'id'=purge_test.id('saet_paastand')::text)
     OR NOT EXISTS (SELECT 1 FROM private.narrative_publication_event WHERE change_set_id=purge_test.id('faelles_saet'))
     OR NOT EXISTS (SELECT 1 FROM private.narrative_publication_event WHERE change_set_id=purge_test.id('saet_withdraw')) THEN
    RAISE EXCEPTION 'PURGE_FIXTURE_KONTROL: sæt med publiceringshændelser';
  END IF;
  -- Ingen blokering (slettegraf §4.3-§4.5, §4.2): kontrolkørsler er terminale, intet er åbent eller udstedt, ingen
  -- persona i X∪Y venter på kontrol, P's C-hændelse er ikke B-batchens eneste, og ingen anden persona har bundet
  -- en række, der slettes med familien.
  IF EXISTS (SELECT 1 FROM private.identity_control_run r
              WHERE coalesce((SELECT e.status FROM private.identity_control_event e WHERE e.control_run_id=r.id
                               ORDER BY e.seq DESC LIMIT 1),'uforseglet') NOT IN ('passed','failed')) THEN
    RAISE EXCEPTION 'PURGE_FIXTURE_KONTROL: åben kontrolkørsel (aaben_koersel)';
  END IF;
  IF EXISTS (SELECT 1 FROM private.reimport_batch WHERE status='open')
     OR EXISTS (SELECT 1 FROM private.reimport_case_batch WHERE status='open')
     OR EXISTS (SELECT 1 FROM private.reimport_authorization WHERE status='issued')
     OR EXISTS (SELECT 1 FROM private.reimport_case_authorization WHERE status='issued')
     OR EXISTS (SELECT 1 FROM private.reimport_event WHERE operation='person_create' AND canonical_person_id=v_p) THEN
    RAISE EXCEPTION 'PURGE_FIXTURE_KONTROL: åben/udstedt batch eller autorisation';
  END IF;
  IF EXISTS (SELECT 1 FROM unnest(v_x||v_y) x WHERE private.persona_awaiting_control(x)) THEN
    RAISE EXCEPTION 'PURGE_FIXTURE_KONTROL: persona venter på kontrol';
  END IF;
  IF EXISTS (SELECT 1 FROM private.reimport_event c
              WHERE c.operation='publication_identity' AND c.canonical_person_id=v_p
                AND NOT EXISTS (SELECT 1 FROM private.reimport_event o
                                 WHERE o.operation='publication_identity' AND o.id<>c.id
                                   AND o.payload->>'persona_batch_id'=c.payload->>'persona_batch_id'
                                   AND o.canonical_person_id IS DISTINCT FROM v_p)) THEN
    RAISE EXCEPTION 'PURGE_FIXTURE_KONTROL: P''s C-hændelse er B-batchens eneste';
  END IF;
  IF EXISTS (SELECT 1 FROM private.interpretation_promotion p JOIN private.interpretation i ON i.id=p.interpretation_id
              WHERE NOT coalesce(i.source_persona_id=ANY(v_x),false)
                AND ((p.target_type='family' AND p.target_id=purge_test.id('fam_del'))
                  OR (p.target_type='fact' AND p.target_id IN (SELECT id FROM public.fact
                                                                WHERE subjekt_type='family' AND subjekt_id=purge_test.id('fam_del')))
                  OR (p.target_type='relation' AND p.target_id=purge_test.id('relation_fam_del')))) THEN
    RAISE EXCEPTION 'PURGE_FIXTURE_KONTROL: anden_promotion';
  END IF;
END $$;

COMMIT;
